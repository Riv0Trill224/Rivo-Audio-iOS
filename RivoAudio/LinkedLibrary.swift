import Foundation
import AVFoundation
import UIKit
import CryptoKit

/// A grant lives as long as a reader/player uses it. Evicting the cache cannot
/// revoke an active player's access. Every successful start has one stop.
final class ScopedSource {
    let url: URL
    private let granted: Bool
    init(_ url: URL) { self.url = url; granted = url.startAccessingSecurityScopedResource() }
    deinit { if granted { url.stopAccessingSecurityScopedResource() } }
}
struct MediaAccess { let url: URL; let scope: ScopedSource? }

extension MusicLibrary {
    func resolve(_ folder: MusicFolder) throws -> ScopedSource {
        if let cached = scopedSources[folder.id] { return cached }
        var stale = false
        let url = try URL(resolvingBookmarkData: folder.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        let scope = ScopedSource(url)
        if stale, let i = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[i].bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil); save()
        }
        if scopedSources.count >= 16 { scopedSources.removeAll() }
        scopedSources[folder.id] = scope
        return scope
    }
    func access(for song: Song) throws -> MediaAccess {
        guard let id = song.sourceFolderID else { return MediaAccess(url: musicDirectory.appendingPathComponent(song.id), scope: nil) }
        guard let folder = folders.first(where: { $0.id == id }) else { throw ServiceError(message: "Vuelve a vincular la carpeta original en Ajustes.") }
        let scope = try resolve(folder)
        let url = folder.singleFile == true ? scope.url : scope.url.appendingPathComponent(song.sourceRelativePath ?? "")
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw ServiceError(message: "Archivo no disponible. Descárgalo en Archivos o vuelve a vincular su carpeta en Ajustes.") }
        return MediaAccess(url: url, scope: scope)
    }
    func linkSource(_ source: URL, singleFile: Bool) async throws {
        let scope = ScopedSource(source)
        let canonical = source.standardizedFileURL.resolvingSymlinksInPath().path
        // A folder already inside Music is indexed in place as local content.
        if MediaFiles.relativePath(of: source, under: musicDirectory) != nil || source.standardizedFileURL == musicDirectory.standardizedFileURL { await scan(force: true); return }
        if singleFile { try MediaFiles.validate(source) }
        else { guard (try source.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { throw ServiceError(message: "Selecciona una carpeta.") } }
        let existing = folders.first { item in
            item.sourcePath == canonical || item.sourcePath == source.standardizedFileURL.path || (try? resolve(item).url.standardizedFileURL.resolvingSymlinksInPath().path) == canonical
        }
        var target = existing?.targetName ?? source.lastPathComponent
        if existing == nil {
            let base = target; var n = 2
            while folders.contains(where: { $0.targetName == target }) || songs.contains(where: { $0.id == target || $0.id.hasPrefix(target + "/") }) { target = "\(base) (\(n))"; n += 1 }
        }
        let bookmark = try source.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        var folder = existing ?? MusicFolder(name: source.lastPathComponent, sourcePath: canonical, targetName: target, bookmark: bookmark)
        folder.bookmark = bookmark; folder.sourcePath = canonical; folder.linked = true; folder.singleFile = singleFile
        if let i = folders.firstIndex(where: { $0.id == folder.id }) { folders[i] = folder } else { folders.append(folder) }
        scopedSources[folder.id] = scope
        try await indexSource(folder, source: scope)
    }
    func indexSource(_ folder: MusicFolder, source: ScopedSource) async throws {
        scanProgress.set("Leyendo carpetas: " + folder.name)
        // Coordinate the listing without copying file bytes; all readers retain the grant.
        let files: [URL] = try await Task.detached(priority: .utility) {
            var coordinationError: NSError?; var listingError: Error?; var found: [URL] = []
            NSFileCoordinator().coordinate(readingItemAt: source.url, options: [], error: &coordinationError) { readable in
                if folder.singleFile == true { found = [readable]; return }
                guard let enumerator = FileManager.default.enumerator(at: readable, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles], errorHandler: { _, error in listingError = error; return false }) else {
                    listingError = ServiceError(message: "No se puede leer la carpeta."); return
                }
                found = (enumerator.allObjects as? [URL] ?? []).filter { MusicLibrary.extensions.contains($0.pathExtension.lowercased()) }
            }
            if let error = coordinationError { throw error }
            if let error = listingError { throw error }
            return found
        }.value
        let old = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        var indexed: [Song] = []; var unavailable = 0
        let linked = songs.filter { $0.sourceFolderID != nil && $0.sourceFolderID != folder.id }
        var roots: [UUID: (URL, Bool)] = [:]
        var grants: [ScopedSource] = []
        for other in folders where other.id != folder.id {
            if let grant = try? resolve(other) { grants.append(grant); roots[other.id] = (grant.url, other.singleFile == true) }
        }
        let sourceRoots = roots
        let otherLocations = await Task.detached(priority: .utility) {
            Set(linked.compactMap { song -> String? in
                guard let id = song.sourceFolderID, let root = sourceRoots[id] else { return nil }
                return (root.1 ? root.0 : root.0.appendingPathComponent(song.sourceRelativePath ?? "")).standardizedFileURL.resolvingSymlinksInPath().path
            })
        }.value
        withExtendedLifetime(grants) {}
        for (offset, url) in files.enumerated() {
            if offset % 20 == 0 { scanProgress.set("Leyendo: " + folder.name, done: offset, total: files.count) }
            if otherLocations.contains(url.standardizedFileURL.resolvingSymlinksInPath().path) { continue }
            let relative = folder.singleFile == true ? "" : (MediaFiles.relativePath(of: url, under: source.url) ?? "")
            guard folder.singleFile == true || !relative.isEmpty else { continue }
            let id = folder.singleFile == true ? folder.targetName : folder.targetName + "/" + relative
            do {
                var song = try await readSong(url, id: id, old: old[id])
                song.sourceFolderID = folder.id; song.sourceRelativePath = relative
                indexed.append(song)
            } catch { unavailable += 1; if let saved = old[id] { indexed.append(saved) } }
        }
        // Missing/offline originals never trigger removal of the retained local copy.
        if indexed.isEmpty && unavailable > 0 { throw ServiceError(message: "Los archivos no están disponibles localmente en Archivos.") }
        let ids = Set(indexed.map(\.id))
        let remaining = songs.filter { $0.sourceFolderID != folder.id && !ids.contains($0.id) }
        songs = (remaining + indexed).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if let i = folders.firstIndex(where: { $0.id == folder.id }) { folders[i].linked = true }
        scanProgress.set("Guardando: " + folder.name, done: files.count, total: files.count)
        try await persistScan()
        scanProgress.set("Leídos: " + folder.name, done: files.count, total: files.count)
    }
    func readSong(_ url: URL, id: String, old: Song?) async throws -> Song {
        let result = try await Self.readMetadata(url, id: id, old: old, info: extras.details[id] ?? TrackDetails())
        pendingDetails[id] = result.1
        return result.0
    }
    nonisolated static func readMetadata(_ url: URL, id: String, old: Song?, info originalInfo: TrackDetails) async throws -> (Song, TrackDetails) {
        try MediaFiles.validate(url)
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        let common = (try? await asset.load(.commonMetadata)) ?? []
        let metadata = (try? await asset.load(.metadata)) ?? []
        func commonText(_ key: AVMetadataKey) async -> String? {
            guard let item = common.first(where: { $0.commonKey?.rawValue == key.rawValue }) else { return nil }
            return try? await item.load(.stringValue)
        }
        func field(_ fragments: [String]) async -> String {
            for item in metadata {
                let key = (item.identifier?.rawValue ?? "").lowercased()
                if fragments.contains(where: { key.contains($0) }), let value = try? await item.load(.stringValue), !value.isEmpty { return value }
            }
            return ""
        }
        let parts = url.deletingPathExtension().lastPathComponent.components(separatedBy: " - ")
        let title = await commonText(.commonKeyTitle)
        let artist = await commonText(.commonKeyArtist)
        let album = await commonText(.commonKeyAlbumName)
        var result = old ?? Song(id: id, title: title ?? (parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : parts[0]), artist: artist ?? (parts.count > 1 ? parts[0] : "Artista desconocido"), album: album ?? "Sin álbum", duration: duration.isFinite ? duration : 0, isVideo: ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()))
        result.duration = duration.isFinite ? duration : 0; result.metadataVerified = title != nil && artist != nil
        if result.albumArtist == nil { result.albumArtist = await field(["albumartist", "album_artist", "tpe2", "aart"]) }
        if result.trackNumber == nil { result.trackNumber = Int((await field(["tracknumber", "trck", "trkn"])).split(separator: "/").first.map(String.init) ?? "") }
        if result.discNumber == nil { result.discNumber = Int((await field(["discnumber", "tpos", "disk"])).split(separator: "/").first.map(String.init) ?? "") }
        // MP4 track/disc tags can be binary rather than strings.
        for item in metadata {
            let key = (item.identifier?.rawValue ?? "").lowercased()
            if (key.contains("trkn") && result.trackNumber == nil) || (key.contains("disk") && result.discNumber == nil),
               let data = try? await item.load(.dataValue), data.count >= 4 {
                let bytes = Array(data); let number = Int(bytes[2]) * 256 + Int(bytes[3])
                if number > 0 { if key.contains("trkn") { result.trackNumber = number } else { result.discNumber = number } }
            }
        }
        var info = originalInfo
        if info.genre.isEmpty { info.genre = await field(["genre", "tcon", "©gen"]) }
        if info.year.isEmpty {
            let commonYear = await commonText(.commonKeyCreationDate)
            let year = commonYear ?? ""
            let alternateYear = year.isEmpty ? await field(["year", "tdrc", "tyer", "©day"]) : year
            info.year = String(alternateYear.prefix(4))
        }
        return (result, info)
    }
    func migrateAndReleaseCopies() async {
        guard !scanning else { return }; scanning = true; defer { scanning = false; scanProgress.finish() }
        var freed: Int64 = 0; var kept = 0
        for folder in folders where folder.singleFile != true {
            do {
                let source = try resolve(folder)
                try await indexSource(folder, source: source)
                let candidates = songs.filter { $0.sourceFolderID == folder.id }
                for (offset, song) in candidates.enumerated() {
                    if offset % 10 == 0 { scanProgress.set("Verificando copias: " + folder.name, done: offset, total: candidates.count) }
                    let copy = musicDirectory.appendingPathComponent(song.id)
                    guard FileManager.default.fileExists(atPath: copy.path) else { continue }
                    let original = try access(for: song)
                    let bytes = try await Task.detached(priority: .utility) { () -> Int64 in
                        guard copy.resolvingSymlinksInPath() != original.url.resolvingSymlinksInPath(), try Self.identical(copy, original.url) else { return 0 }
                        let count = Int64((try copy.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
                        try FileManager.default.removeItem(at: copy)
                        return count
                    }.value
                    if bytes > 0 { freed += bytes } else { kept += 1 }
                }
                scanProgress.set("Verificación terminada: " + folder.name, done: candidates.count, total: candidates.count)
            } catch { kept += 1 }
        }
        message = "Copias verificadas liberadas: \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)).\nSe conservaron \(kept) archivos o fuentes sin verificar. Los originales no se borraron."
    }
    nonisolated static func identical(_ a: URL, _ b: URL) throws -> Bool {
        guard (try a.resourceValues(forKeys: [.fileSizeKey])).fileSize == (try b.resourceValues(forKeys: [.fileSizeKey])).fileSize else { return false }
        func digest(_ url: URL) throws -> SHA256.Digest {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            var hash = SHA256()
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
            return hash.finalize()
        }
        return try digest(a) == digest(b)
    }
    func artworkURL(_ song: Song) -> URL {
        let folder = documents.appendingPathComponent("ArtworkCache")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(SHA256.hash(data: Data(song.id.utf8)).map { String(format: "%02x", $0) }.joined() + ".jpg")
    }
    func loadArtwork(_ song: Song) async -> UIImage? {
        if let image = image(for: song) { return image }
        if missingArtworkIDs.contains(song.id) { return nil }
        if let task = artworkTasks[song.id] { return await task.value }
        guard let media = try? access(for: song) else { return nil }
        let target = artworkURL(song)
        let task = Task<UIImage?, Never> {
            let asset = AVURLAsset(url: media.url)
            let items = (try? await asset.load(.commonMetadata)) ?? []
            guard let item = items.first(where: { $0.commonKey == .commonKeyArtwork }), let data = try? await item.load(.dataValue) else { return nil }
            let image = await Task.detached(priority: .utility) { Self.thumbnail(data) }.value
            if let jpeg = image?.jpegData(compressionQuality: 0.8) { try? jpeg.write(to: target, options: .atomic) }
            withExtendedLifetime(media) {}
            return image
        }
        artworkTasks[song.id] = task
        let result = await task.value; artworkTasks.removeValue(forKey: song.id)
        if result == nil { missingArtworkIDs.insert(song.id) }
        return image(for: song) ?? result
    }
}

extension MusicLibrary {
    func relinkFolder(_ id: UUID, source: URL) async {
        guard !scanning else { return }; scanning = true; defer { scanning = false; scanProgress.finish() }
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let previous = folders[index]
        do {
            let grant = ScopedSource(source)
            var folder = previous
            folder.bookmark = try source.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            folder.sourcePath = source.standardizedFileURL.resolvingSymlinksInPath().path
            folder.linked = true
            folders[index] = folder; scopedSources[id] = grant
            try await indexSource(folder, source: grant)
            message = "Carpeta vinculada. Se conservaron los identificadores de pistas y playlists."
        } catch { folders[index] = previous; scopedSources.removeValue(forKey: id); message = "No se pudo vincular: \(error.localizedDescription)" }
    }
}
