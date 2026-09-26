import Foundation
import Network
import Darwin
import Combine

/// Simple foreground-only FTP upload service for a trusted home LAN.
/// One control connection and one passive data connection at a time.
@MainActor final class FTPServer: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var address = ""
    @Published private(set) var password = ""
    @Published var status = "Servidor detenido"
    private var listener: NWListener?
    private var passive: NWListener?
    private var control: NWConnection?
    private var dataConnection: NWConnection?
    private var pendingUpload: String?
    private var authenticated = false
    private var input = Data()
    weak var library: MusicLibrary?
    private let workQueue = DispatchQueue(label: "com.riv0trill.rivoaudio.ftp")

    func start() {
        guard !running else { return }
        do {
            let listener = try NWListener(using: .tcp, on: 2121)
            password = String(format: "%06d", Int.random(in: 0...999999))
            address = localIPv4() ?? "IP del iPhone"
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    if case .failed(let error) = state { self?.status = error.localizedDescription; self?.stop() }
                }
            }
            listener.start(queue: workQueue)
            self.listener = listener
            running = true
            status = "Esperando conexión en \(address):2121"
        } catch { status = error.localizedDescription }
    }
    func stop() {
        listener?.cancel(); passive?.cancel(); control?.cancel(); dataConnection?.cancel()
        listener = nil; passive = nil; control = nil; dataConnection = nil
        running = false; password = ""; pendingUpload = nil; authenticated = false
        status = "Servidor detenido"
    }
    private func accept(_ connection: NWConnection) {
        control?.cancel(); passive?.cancel()
        control = connection; authenticated = false; input = Data()
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .ready = state { self?.reply("220 RIVO Audio FTP ready") }
            }
        }
        connection.start(queue: workQueue)
        receiveCommands(connection)
    }
    private func reply(_ text: String) {
        control?.send(content: Data((text + "\r\n").utf8), completion: .contentProcessed { _ in })
    }
    private func receiveCommands(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, _ in
            Task { @MainActor in
                guard let self, self.control === connection else { return }
                if let data { self.input.append(data) }
                while let range = self.input.range(of: Data("\n".utf8)) {
                    let line = String(decoding: self.input[..<range.lowerBound], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    self.input.removeSubrange(..<range.upperBound)
                    self.command(line)
                }
                if complete { self.control = nil; self.passive?.cancel() }
                else { self.receiveCommands(connection) }
            }
        }
    }
    private func command(_ line: String) {
        let pieces = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = pieces.first?.uppercased() else { return }
        let argument = pieces.count > 1 ? pieces[1] : ""
        switch verb {
        case "USER": reply(argument == "rivo" ? "331 Password required" : "530 Use user rivo")
        case "PASS": authenticated = argument == password; reply(authenticated ? "230 Logged in" : "530 Invalid password")
        case "QUIT": reply("221 Goodbye"); control?.cancel(); control = nil
        case "NOOP": reply("200 OK")
        default:
            guard authenticated else { reply("530 Log in first"); return }
            switch verb {
            case "SYST": reply("215 UNIX Type: L8")
            case "FEAT": reply("211-Features\r\n UTF8\r\n EPSV\r\n211 End")
            case "OPTS": reply("200 UTF8 on")
            case "TYPE": reply("200 Type set")
            case "PWD", "XPWD": reply("257 \"/\" is current directory")
            case "CWD", "CDUP": reply(argument == "/" || argument == "." || verb == "CDUP" ? "250 OK" : "550 Use / only")
            case "PASV", "EPSV": openPassive(extended: verb == "EPSV")
            case "STOR":
                let filename = (argument as NSString).lastPathComponent
                guard !filename.isEmpty, filename != ".", filename != "..",
                      MusicLibrary.extensions.contains((filename as NSString).pathExtension.lowercased()) else {
                    reply("550 Unsupported filename"); return
                }
                guard passive != nil else { reply("425 Use PASV first"); return }
                pendingUpload = filename
                reply("150 Opening binary data connection")
                if let connection = dataConnection { upload(connection) }
            case "LIST", "NLST":
                guard passive != nil else { reply("425 Use PASV first"); return }
                reply("150 Opening listing")
                if let connection = dataConnection { sendListing(connection, namesOnly: verb == "NLST") }
                else { pendingUpload = verb } // list after data connection becomes ready
            default: reply("502 Command not implemented")
            }
        }
    }
    private func openPassive(extended: Bool) {
        passive?.cancel(); dataConnection?.cancel(); dataConnection = nil; pendingUpload = nil
        do {
            let listener = try NWListener(using: .tcp, on: .any)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self else { return }
                    self.dataConnection = connection
                    connection.start(queue: self.workQueue)
                    if let pending = self.pendingUpload {
                        if pending == "LIST" || pending == "NLST" { self.sendListing(connection, namesOnly: pending == "NLST") }
                        else { self.upload(connection) }
                    }
                }
            }
            passive = listener
            // NWListener exposes the assigned port once the listener is ready.
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    if case .ready = state, let port = listener.port?.rawValue {
                        if extended { self.reply("229 Entering Extended Passive Mode (|||\(port)|)") }
                        else {
                            let octets = self.address.split(separator: ".")
                            guard octets.count == 4 else { self.reply("425 No IPv4 address"); return }
                            self.reply("227 Entering Passive Mode (\(octets.joined(separator: ",")),\(port / 256),\(port % 256))")
                        }
                    }
                }
            }
            listener.start(queue: workQueue)
        } catch { reply("425 Cannot open data listener") }
    }
    private func upload(_ connection: NWConnection) {
        guard let filename = pendingUpload, filename != "LIST", filename != "NLST", let library else { return }
        pendingUpload = nil
        let directory = library.musicDirectory
        let target = directory.appendingPathComponent(filename)
        let temporary = directory.appendingPathComponent(".upload-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: temporary) else { reply("451 Cannot write file"); return }
        status = "Recibiendo \(filename)"
        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] bytes, _, done, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let bytes { try? handle.write(contentsOf: bytes) }
                    if done || error != nil {
                        try? handle.close(); connection.cancel()
                        self.passive?.cancel(); self.passive = nil; self.dataConnection = nil
                        if error == nil {
                            do {
                                let destination = FileManager.default.fileExists(atPath: target.path) ? self.uniqueTarget(filename, in: directory) : target
                                try FileManager.default.moveItem(at: temporary, to: destination)
                                self.reply("226 Transfer complete")
                                self.status = "Recibido: \(destination.lastPathComponent)"
                                Task { await library.scan() }
                            } catch { self.reply("451 Save failed"); try? FileManager.default.removeItem(at: temporary) }
                        } else { self.reply("426 Transfer aborted"); try? FileManager.default.removeItem(at: temporary) }
                    } else { receive() }
                }
            }
        }
        receive()
    }
    private func uniqueTarget(_ filename: String, in directory: URL) -> URL {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var count = 2
        while true {
            let candidate = directory.appendingPathComponent("\(name) (\(count)).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            count += 1
        }
    }
    private func sendListing(_ connection: NWConnection, namesOnly: Bool) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: library?.musicDirectory.path ?? "")) ?? []
        let listing = names.filter { MusicLibrary.extensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .map { namesOnly ? $0 : "-rw-r--r-- 1 rivo rivo 0 Jan 01 00:00 \($0)" }.joined(separator: "\r\n") + "\r\n"
        connection.send(content: Data(listing.utf8), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in
                connection.cancel(); self?.reply("226 Listing complete")
                self?.passive?.cancel(); self?.passive = nil; self?.dataConnection = nil; self?.pendingUpload = nil
            }
        })
    }
    private func localIPv4() -> String? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return nil }
        defer { freeifaddrs(first) }
        var cursor = first
        while let pointer = cursor {
            let interface = pointer.pointee
            if let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
               String(cString: interface.ifa_name) == "en0" {
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                if inet_ntop(AF_INET, &value, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil { return String(cString: buffer) }
            }
            cursor = interface.ifa_next
        }
        return nil
    }
}
