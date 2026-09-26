import Foundation
import Combine
import CryptoKit
import Network

struct LastFMFailure: LocalizedError {
    let code: Int
    let message: String
    var errorDescription: String? { message }
    var retryable: Bool { [11, 16, 29, -1].contains(code) }
}

enum LastFMProtocol {
    static func signature(_ params: [String: String], secret: String) -> String {
        let raw = params.filter { !["format", "callback", "api_sig"].contains($0.key) }
            .sorted { $0.key < $1.key }.map { $0.key + $0.value }.joined() + secret
        return Insecure.MD5.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func form(_ params: [String: String]) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return params.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
    }
    static func accepted(_ json: [String: Any]) -> Bool {
        guard let scrobbles = json["scrobbles"] as? [String: Any], let attributes = scrobbles["@attr"] as? [String: Any] else { return false }
        return String(describing: attributes["accepted"] ?? "0") == "1"
    }
}

private struct LastFMCredentials: Codable {
    var key = ""
    var secret = ""
    var session = ""
    var user = ""
}
struct PendingScrobble: Codable, Identifiable {
    var id = UUID()
    let account: String
    let artist: String
    let title: String
    let album: String
    let duration: Int
    let timestamp: Int
    var rejection: String? = nil
}

@MainActor final class LastFMClient: ObservableObject {
    @Published private(set) var username = ""
    @Published private(set) var configured = false
    @Published private(set) var authorizing = false
    @Published private(set) var busy = false
    @Published var status = "Conecta Last.fm para enviar tus escuchas."
    @Published var enabled = false { didSet { UserDefaults.standard.set(enabled, forKey: "lastfm.enabled") } }
    @Published private(set) var pending: [PendingScrobble] = []
    private var credentials = LastFMCredentials()
    private var token: String?
    private var flushing = false
    private var revision = 0
    private let monitor = NWPathMonitor()
    private let path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("lastfm-queue.json")
    var connected: Bool { !credentials.session.isEmpty && !username.isEmpty }

    init() {
        if let data = SecureStore.load(), let stored = try? JSONDecoder().decode(LastFMCredentials.self, from: data) {
            credentials = stored; username = stored.user; configured = !stored.key.isEmpty && !stored.secret.isEmpty
        }
        enabled = UserDefaults.standard.bool(forKey: "lastfm.enabled")
        if let data = try? Data(contentsOf: path), let queue = try? JSONDecoder().decode([PendingScrobble].self, from: data) { pending = queue }
        monitor.pathUpdateHandler = { [weak self] network in
            if network.status == .satisfied { Task { @MainActor in await self?.flush() } }
        }
        monitor.start(queue: DispatchQueue(label: "rivo.lastfm.network"))
    }
    func configure(key: String, secret: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count == 32, secret.count == 32, key.allSatisfy(\.isHexDigit), secret.allSatisfy(\.isHexDigit) else {
            throw ServiceError(message: "Introduce la API key y el shared secret de 32 caracteres de tu cuenta API de Last.fm.")
        }
        let value = LastFMCredentials(key: key, secret: secret)
        try SecureStore.save(JSONEncoder().encode(value))
        revision += 1; credentials = value; username = ""; configured = true; token = nil; authorizing = false; enabled = false
        status = "Credenciales guardadas. Autoriza tu cuenta de Last.fm."
    }
    func beginAuthorization() async -> URL? {
        guard configured, !busy else { return nil }
        busy = true; defer { busy = false }
        let currentRevision = revision
        do {
            let response = try await call("auth.getToken", [:])
            guard revision == currentRevision, let value = response["token"] as? String else { throw ServiceError(message: "No se recibió un token de autorización.") }
            token = value; authorizing = true
            status = "Autoriza en Last.fm y regresa para pulsar ‘Ya autoricé’."
            return OnlineSupport.url("https://www.last.fm/api/auth/", ["api_key": credentials.key, "token": value])
        } catch { status = error.localizedDescription; return nil }
    }
    func finishAuthorization() async {
        guard let token, !busy else { return }
        busy = true; defer { busy = false }
        let currentRevision = revision
        do {
            let response = try await call("auth.getSession", ["token": token])
            guard revision == currentRevision, let session = response["session"] as? [String: Any],
                  let key = session["key"] as? String, let name = session["name"] as? String else { throw ServiceError(message: "Last.fm no devolvió una sesión válida.") }
            var saved = credentials; saved.session = key; saved.user = name
            try SecureStore.save(JSONEncoder().encode(saved))
            credentials = saved; username = name; self.token = nil; authorizing = false; enabled = true
            status = "Conectado como \(name)."; await flush()
        } catch { status = error.localizedDescription }
    }
    func disconnect() {
        var value = credentials; value.session = ""; value.user = ""
        do {
            try SecureStore.save(JSONEncoder().encode(value))
            revision += 1; credentials = value; username = ""; enabled = false; token = nil; authorizing = false
            status = "Cuenta desconectada. La cola conserva el nombre de la cuenta original."
        } catch { status = error.localizedDescription }
    }
    func nowPlaying(_ song: Song) {
        guard connected, enabled else { return }
        guard song.metadataVerified == true else { status = "Confirma título y artista en Editar antes de enviar esta canción a Last.fm."; return }
        Task {
            do { _ = try await call("track.updateNowPlaying", parameters(song)) }
            catch { status = error.localizedDescription }
        }
    }
    func enqueue(_ song: Song, startedAt: Date) {
        guard connected, enabled, song.metadataVerified == true, song.duration > 30 else { return }
        pending.append(PendingScrobble(account: username, artist: song.artist, title: song.title, album: song.album,
            duration: Int(song.duration), timestamp: Int(startedAt.timeIntervalSince1970)))
        persistQueue()
        Task { await flush() }
    }
    func flush() async {
        guard connected, enabled, !flushing else { return }
        flushing = true; defer { flushing = false }
        let account = username; let epoch = revision
        // A failed entry remains visible; transient failures are retried on reconnect/foreground.
        while connected, enabled, revision == epoch,
              let entry = pending.first(where: { $0.account == account && $0.rejection == nil }) {
            do {
                let response = try await call("track.scrobble", ["artist": entry.artist, "track": entry.title,
                    "album": entry.album, "duration": String(entry.duration), "timestamp": String(entry.timestamp)])
                if LastFMProtocol.accepted(response) {
                    pending.removeAll { $0.id == entry.id }; status = "Enviado: \(entry.title)"
                } else { reject(entry.id, "Last.fm no aceptó esta escucha; revisa sus metadatos o fecha.") }
                persistQueue()
            } catch let error as LastFMFailure {
                guard revision == epoch else { return }
                status = error.localizedDescription
                if error.code == 9 {
                    credentials.session = ""; username = ""; enabled = false
                    try? SecureStore.save(JSONEncoder().encode(credentials)); return
                }
                if error.retryable { return }
                if [10, 13, 26].contains(error.code) { enabled = false; return }
                reject(entry.id, error.localizedDescription); persistQueue()
            } catch { status = "Sin conexión con Last.fm. Las escuchas se conservarán para reintentar."; return }
        }
    }
    func clearRejected() { pending.removeAll { $0.account == username && $0.rejection != nil }; persistQueue() }
    private func reject(_ id: UUID, _ reason: String) {
        if let index = pending.firstIndex(where: { $0.id == id }) { pending[index].rejection = reason }
        status = reason
    }
    private func persistQueue() {
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(pending).write(to: path, options: .atomic)
        } catch { status = "No se pudo guardar la cola de Last.fm: \(error.localizedDescription)" }
    }
    private func parameters(_ song: Song) -> [String: String] {
        ["artist": song.artist, "track": song.title, "album": song.album == "Sin álbum" ? "" : song.album, "duration": String(Int(song.duration))]
    }
    private func call(_ method: String, _ fields: [String: String]) async throws -> [String: Any] {
        var params = fields
        params["method"] = method; params["api_key"] = credentials.key
        if method.hasPrefix("track.") { params["sk"] = credentials.session }
        params["api_sig"] = LastFMProtocol.signature(params, secret: credentials.secret)
        params["format"] = "json"
        var request: URLRequest
        if method.hasPrefix("auth.") { request = URLRequest(url: OnlineSupport.url("https://ws.audioscrobbler.com/2.0/", params)) }
        else {
            request = URLRequest(url: URL(string: "https://ws.audioscrobbler.com/2.0/")!)
            request.httpMethod = "POST"; request.httpBody = Data(LastFMProtocol.form(params).utf8)
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = 25; request.setValue(OnlineSupport.agent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LastFMFailure(code: -1, message: "Respuesta no válida de Last.fm.") }
        if let code = json["error"] as? Int { throw LastFMFailure(code: code, message: json["message"] as? String ?? "Error de Last.fm \(code)") }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw LastFMFailure(code: -1, message: "Last.fm no está disponible. Se reintentará después.") }
        return json
    }
}
