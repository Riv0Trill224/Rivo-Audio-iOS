import Foundation
import CryptoKit
import ImageIO
import UIKit

struct TrackDetail: Sendable {
    let tags: Tags
    let artwork: Data
    let lrc: String
    let lrcHash: String?
    let url: URL
}

actor FileService {
    static let shared = FileService()
    static let extensions: Set<String> = ["mp3", "m4a", "mp4", "flac", "ogg", "opus", "wav", "aif", "aiff", "ape", "wv", "wma", "dsf", "dff", "mpc"]
    private var roots: [UUID: URL] = [:]
    private let fm = FileManager.default
    private var history: [HistoryEntry] = []
    private var thumbnailCache: [String: Data] = [:]
    private var dataRoot: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RivoMetadataEditor", isDirectory: true)
    }
    private var backupRoot: URL { dataRoot.appendingPathComponent("Backups", isDirectory: true) }

    func register(_ folder: MusicFolder) throws -> MusicFolder {
        var stale = false
        let url = try URL(resolvingBookmarkData: folder.bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        roots[folder.id] = url
        var updated = folder
        if stale {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            updated.bookmark = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        return updated
    }
    func folder(from url: URL, id: UUID = UUID()) throws -> MusicFolder {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw RivoError.message("Selecciona una carpeta de música.")
        }
        // Reuse permission identity when the same folder is picked again.
        let existingID = roots.first { $0.value.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }?.key ?? id
        let bookmark = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        roots[existingID] = url
        return MusicFolder(id: existingID, name: url.lastPathComponent, bookmark: bookmark)
    }
    private func access<T>(_ id: UUID, _ work: (URL) throws -> T) throws -> T {
        guard let root = roots[id] else { throw RivoError.message("Vuelve a seleccionar la carpeta para conceder acceso.") }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        return try work(root)
    }
    private func path(_ relative: String, root: URL) throws -> URL {
        try FolderPaths.resolve(relative, root: root)
    }
    private func sidecar(_ audio: URL, root: URL) throws -> URL {
        let parent = audio.deletingLastPathComponent()
        let base = audio.deletingPathExtension().lastPathComponent
        let matches = try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).filter {
            $0.pathExtension.lowercased() == "lrc" && $0.deletingPathExtension().lastPathComponent == base
        }
        guard matches.count <= 1 else { throw RivoError.message("Hay varios LRC para este audio. Conserva una sola versión en su carpeta.") }
        let candidate = matches.first ?? audio.deletingPathExtension().appendingPathExtension("lrc")
        return try path(FolderPaths.relative(candidate, root: root), root: root)
    }
    private func sidecarState(_ url: URL) -> SidecarState {
        guard fm.fileExists(atPath: url.path) else { return .missing }
        do {
            return try coordinated(url, write: false) { u in
                guard try stamp(u).size <= 2_000_000 else { return .unreadable }
                let bytes = try Data(contentsOf: u)
                guard let text = String(data: bytes, encoding: .utf8) else { return .unreadable }
                return (try? LRC.validate(text)) != nil ? .synchronized : .invalid
            }
        } catch { return .unreadable }
    }

    private func coordinated<T>(_ url: URL, write: Bool, _ work: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        if write {
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { u in result = Result { try work(u) } }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { u in result = Result { try work(u) } }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw RivoError.message("El proveedor de Archivos no respondió.") }
        return try result.get()
    }
    private func stamp(_ url: URL) throws -> FileStamp {
        let a = try fm.attributesOfItem(atPath: url.path)
        return FileStamp(size: (a[.size] as? NSNumber)?.int64Value ?? 0, modified: a[.modificationDate] as? Date ?? .distantPast)
    }
    private func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { digest.update(data: chunk) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func bridge(_ url: URL, artwork: Bool) throws -> [String: Any] {
        let result = RMEBridge.read(path: url.path, artwork: artwork)
        if let e = result["error"] as? String { throw RivoError.message(e) }
        return result
    }
    private func readTrack(_ url: URL, root: URL, folderID: UUID, relative: String) throws -> Track {
        let state = sidecarState(try sidecar(url, root: root))
        return try coordinated(url, write: false) { u in
            let m = try bridge(u, artwork: false)
            return Track(folderID: folderID, relativePath: relative, tags: Tags(fields: m["fields"] as? [String: String] ?? [:]),
                         duration: m["duration"] as? Double ?? 0, bitrate: m["bitrate"] as? Int ?? 0,
                         sampleRate: m["sampleRate"] as? Int ?? 0, stamp: try stamp(u),
                         hasLRC: state != .missing, hasArtwork: m["hasArtwork"] as? Bool ?? false,
                         lrcState: state, embeddedSyncedLyrics: m["embeddedSyncedLyrics"] as? String, embeddedDetected: m["hasEmbeddedLyrics"] as? Bool)
        }
    }
    func scan(_ folders: [MusicFolder], progress: @Sendable (Int, Int, String) async -> Void) async throws -> [Track] {
        var files: [(UUID, URL, String)] = []
        var seen: Set<String> = []
        for folder in folders {
            try Task.checkCancellation()
            try access(folder.id) { root in
                var enumerationError: Error?
                guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { _, error in enumerationError = error; return false }) else {
                    throw RivoError.message("No se pudo abrir la carpeta \(folder.name).")
                }
                for case let url as URL in e {
                    try Task.checkCancellation()
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isSymbolicLink != true else { e.skipDescendants(); continue }
                    guard values.isRegularFile == true, Self.extensions.contains(url.pathExtension.lowercased()), seen.insert(url.resolvingSymlinksInPath().path).inserted else { continue }
                    files.append((folder.id, url, try FolderPaths.relative(url, root: root)))
                }
                if let enumerationError { throw enumerationError }
            }
        }
        var tracks: [Track] = []
        for (index, entry) in files.enumerated() {
            try Task.checkCancellation()
            do {
                let t = try access(entry.0) { root in try readTrack(path(entry.2, root: root), root: root, folderID: entry.0, relative: entry.2) }
                tracks.append(t)
            } catch {
                tracks.append(Track(folderID: entry.0, relativePath: entry.2, tags: Tags(), duration: 0, bitrate: 0,
                                    sampleRate: 0, stamp: FileStamp(size: 0, modified: .distantPast), hasLRC: false, error: error.localizedDescription))
            }
            await progress(index + 1, files.count, entry.1.lastPathComponent)
        }
        return tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func detail(_ track: Track) throws -> TrackDetail {
        try access(track.folderID) { root in
            let url = try path(track.relativePath, root: root)
            let m = try coordinated(url, write: false) { try bridge($0, artwork: true) }
            let lrcURL = try sidecar(url, root: root)
            let exists = fm.fileExists(atPath: lrcURL.path)
            let lrc: (String, String?) = exists ? try coordinated(lrcURL, write: false) { u in
                guard try stamp(u).size <= 2_000_000 else { throw RivoError.message("La letra supera 2 MB.") }
                let bytes = try Data(contentsOf: u)
                guard bytes.count <= 2_000_000, let text = String(data: bytes, encoding: .utf8) else {
                    throw RivoError.message("La letra existente no es UTF-8 o supera 2 MB.")
                }
                return (text, try hash(u))
            } : ("", nil)
            return TrackDetail(tags: Tags(fields: m["fields"] as? [String: String] ?? [:]), artwork: m["artwork"] as? Data ?? Data(), lrc: exists ? lrc.0 : ((m["embeddedSyncedLyrics"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (m["fields"] as? [String: String])?["LYRICS"] ?? ""), lrcHash: lrc.1, url: url)
        }
    }
    func thumbnail(_ track: Track) throws -> Data {
        let key = track.id + String(track.stamp.modified.timeIntervalSince1970) + String(track.stamp.size)
        if let cached = thumbnailCache[key] { return cached }
        let data = try access(track.folderID) { root -> Data in
            try coordinated(path(track.relativePath, root: root), write: false) { u in
                let m = try bridge(u, artwork: true)
                let raw = m["artwork"] as? Data ?? Data()
                return (try? ArtworkCodec.prepare(raw, maxPixels: 160)) ?? Data()
            }
        }
        if thumbnailCache.count >= 128 { thumbnailCache.removeAll(keepingCapacity: true) }
        thumbnailCache[key] = data
        return data
    }
    func refresh(_ track: Track) throws -> Track {
        try access(track.folderID) { root in try readTrack(path(track.relativePath, root: root), root: root, folderID: track.folderID, relative: track.relativePath) }
    }
    private func prepareHistory() throws {
        try fm.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        if history.isEmpty, let bytes = try? Data(contentsOf: dataRoot.appendingPathComponent("history.json")) {
            history = try JSONDecoder().decode([HistoryEntry].self, from: bytes)
        }
    }
    private func remember(_ entry: HistoryEntry) throws {
        history.insert(entry, at: 0)
        try JSONEncoder().encode(history).write(to: dataRoot.appendingPathComponent("history.json"), options: .atomic)
    }
    func loadHistory() throws -> [HistoryEntry] { try prepareHistory(); return history }

    func save(_ track: Track, patch: [String: String], artwork: Data?, removeArtwork: Bool) throws -> Track {
        try prepareHistory()
        try access(track.folderID) { root in
            let original = try path(track.relativePath, root: root)
            try coordinated(original, write: true) { u in
                guard try stamp(u) == track.stamp else { throw RivoError.message("El archivo cambió desde el análisis. Vuelve a escanear antes de guardarlo.") }
                let id = UUID()
                let backupName = id.uuidString + "." + u.pathExtension
                let backup = backupRoot.appendingPathComponent(backupName)
                let staging = u.deletingLastPathComponent().appendingPathComponent(".rivo-\(id.uuidString).\(u.pathExtension)")
                defer { try? fm.removeItem(at: staging) }
                let before = try bridge(u, artwork: false)
                try fm.copyItem(at: u, to: backup)
                try fm.copyItem(at: u, to: staging)
                let result = RMEBridge.write(path: staging.path, fields: patch, artwork: artwork, removeArtwork: removeArtwork)
                if let e = result["error"] as? String { throw RivoError.message(e) }
                let verified = try bridge(staging, artwork: artwork != nil || removeArtwork)
                let tags = Tags(fields: verified["fields"] as? [String: String] ?? [:])
                for (k, v) in patch {
                    let actual = k == "ITUNESADVISORY" && tags[k].isEmpty ? "0" : tags[k]
                    guard actual == v || (v.isEmpty && actual == "0" && k == "ITUNESADVISORY") else {
                        throw RivoError.message("Falló la verificación del campo \(k). El original se conserva.")
                    }
                }
                if let artwork { guard verified["artwork"] as? Data == artwork else { throw RivoError.message("No se pudo verificar la portada guardada.") } }
                guard abs((before["duration"] as? Double ?? 0) - (verified["duration"] as? Double ?? 0)) < 0.15 else {
                    throw RivoError.message("La duración del audio cambió. El original se conserva.")
                }
                let entry = HistoryEntry(id: id, date: Date(), folderID: track.folderID, relativePath: track.relativePath,
                                         backupName: backupName, afterHash: try hash(staging), description: "Metadatos / portada")
                // Persist recovery information before committing, so a crash never loses the backup identity.
                try remember(entry)
                _ = try fm.replaceItemAt(u, withItemAt: staging)
            }
        }
        return try refresh(track)
    }

    func saveLRC(_ track: Track, text: String, expectedExistingHash: String? = nil) throws -> Track {
        try LRC.validate(text)
        try prepareHistory()
        try access(track.folderID) { root in
            let audio = try path(track.relativePath, root: root)
            guard fm.fileExists(atPath: audio.path), try stamp(audio) == track.stamp else {
                throw RivoError.message("El audio cambió o ya no existe. Vuelve a escanear antes de guardar la letra.")
            }
            let url = try sidecar(audio, root: root)
            let relative = try FolderPaths.relative(url, root: root)
            try coordinated(url, write: true) { u in
                let exists = fm.fileExists(atPath: u.path)
                if exists {
                    guard let expectedExistingHash, try hash(u) == expectedExistingHash else {
                        throw RivoError.message("Ya existe una letra o cambió mientras la editabas. Ábrela antes de reemplazarla.")
                    }
                } else if expectedExistingHash != nil {
                    throw RivoError.message("La letra existente desapareció. Vuelve a abrir el editor.")
                }
                let id = UUID()
                let backupName = exists ? id.uuidString + ".lrc" : nil
                if let backupName { try fm.copyItem(at: u, to: backupRoot.appendingPathComponent(backupName)) }
                let bytes = Data(text.utf8)
                let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                let entry = HistoryEntry(id: id, date: Date(), folderID: track.folderID, relativePath: relative,
                                         backupName: backupName, afterHash: digest, description: "Letra sincronizada")
                try remember(entry)
                if exists { try bytes.write(to: u, options: .atomic) }
                else {
                    let staging = u.deletingLastPathComponent().appendingPathComponent(".rivo-\(id.uuidString).lrc")
                    defer { try? fm.removeItem(at: staging) }
                    try bytes.write(to: staging, options: .atomic)
                    try fm.moveItem(at: staging, to: u)
                }
            }
        }
        return try refresh(track)
    }
    func undo(_ entry: HistoryEntry) throws {
        try prepareHistory()
        try access(entry.folderID) { root in
            let url = try path(entry.relativePath, root: root)
            try coordinated(url, write: true) { u in
                guard fm.fileExists(atPath: u.path), try hash(u) == entry.afterHash else {
                    throw RivoError.message("Hay cambios posteriores en este archivo. No se puede deshacer sin sobrescribirlos.")
                }
                if let name = entry.backupName {
                    let staging = u.deletingLastPathComponent().appendingPathComponent(".rivo-undo-" + UUID().uuidString + "." + u.pathExtension)
                    defer { try? fm.removeItem(at: staging) }
                    try fm.copyItem(at: backupRoot.appendingPathComponent(name), to: staging)
                    _ = try fm.replaceItemAt(u, withItemAt: staging)
                } else { try fm.removeItem(at: u) }
            }
        }
        history.removeAll { $0.id == entry.id }
        try JSONEncoder().encode(history).write(to: dataRoot.appendingPathComponent("history.json"), options: .atomic)
        if let name = entry.backupName { try? fm.removeItem(at: backupRoot.appendingPathComponent(name)) }
    }

    // The returned closure scope must stay active for playback. Caller balances stopAccessing.
    func playbackURL(_ track: Track) throws -> (URL, URL) {
        guard let root = roots[track.folderID] else { throw RivoError.message("Falta permiso de la carpeta.") }
        _ = root.startAccessingSecurityScopedResource()
        do { return (try path(track.relativePath, root: root), root) }
        catch { root.stopAccessingSecurityScopedResource(); throw error }
    }
}
