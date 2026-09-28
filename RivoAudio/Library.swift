import Foundation
import AVFoundation
import UIKit
import Combine
import ImageIO

struct Song: Identifiable, Codable, Hashable {
    var id: String // Relative path under Documents/Music; stable across launches.
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var rating: Int = 0
    var chartNote: String = ""
    var isVideo: Bool = false
    var playCount: Int = 0
    var artworkFile: String? = nil
    var lyrics: String? = nil
    var metadataVerified: Bool? = nil
}

struct MusicFolder: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var sourcePath: String
    var targetName: String
    var bookmark: Data
}

@MainActor final class MusicLibrary: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var folders: [MusicFolder] = []
    @Published var message: String? = nil
    @Published var artistPhotos: [String: String] = [:]
    @Published var photoCredits: [String: ArtistPhotoCredit] = [:]
    @Published var photoStatus: [String: String] = [:]
    var photoRequests: Set<String> = []
    var photoAttempts: [String: Date] = [:]
    let documents: URL
    var musicDirectory: URL { documents.appendingPathComponent("Music", isDirectory: true) }
    private var indexURL: URL { documents.appendingPathComponent("library.json") }
    private var foldersURL: URL { documents.appendingPathComponent("musicFolders.json") }
    private var photosURL: URL { documents.appendingPathComponent("artistPhotos.json") }
    private var photoAttemptsURL: URL { documents.appendingPathComponent("artistPhotoAttempts.json") }
    private let artworkCache = NSCache<NSString, UIImage>()
    private var missingArtwork = Set<String>()
    static let extensions: Set<String> = ["mp3", "m4a", "aac", "alac", "wav", "aif", "aiff", "caf", "flac", "mp4", "m4v", "mov"]

    init(documents: URL? = nil, scanOnStart: Bool = true) {
        self.documents = documents ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL), let value = try? JSONDecoder().decode([Song].self, from: data) { songs = value }
        if let data = try? Data(contentsOf: foldersURL), let value = try? JSONDecoder().decode([MusicFolder].self, from: data) { folders = value }
        if let data = try? Data(contentsOf: photosURL), let value = try? JSONDecoder().decode([String: String].self, from: data) { artistPhotos = value }
        if let data = try? Data(contentsOf: self.documents.appendingPathComponent("artistPhotoCredits.json")),
           let saved = try? JSONDecoder().decode([String: ArtistPhotoCredit].self, from: data) { photoCredits = saved }
        if let data = try? Data(contentsOf: photoAttemptsURL),
           let saved = try? JSONDecoder().decode([String: Date].self, from: data) { photoAttempts = saved }
        artworkCache.totalCostLimit = 24 * 1024 * 1024
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-fixture") {
            let longMetadata = ProcessInfo.processInfo.arguments.contains("--ui-long-metadata")
            var fixture = Song(id: "Neon.wav",
                               title: longMetadata ? "Peso [Prod. By ASAP Ty Beats] — Extended title for narrow screens" : "Neon Nights",
                               artist: longMetadata ? "A$AP Rocky" : "Rivo Sessions",
                               album: longMetadata ? "LiveLoveA$AP — A very long album name" : "Prueba de interfaz", duration: 3)
            if longMetadata {
                let artwork = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { context in
                    UIColor.systemPurple.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
                    UIColor.systemOrange.setFill()
                    context.fill(CGRect(x: 300, y: 0, width: 300, height: 600))
                }
                let name = "layout-fixture.jpg"
                try? artwork.jpegData(compressionQuality: 0.9)?.write(to: self.documents.appendingPathComponent(name))
                fixture.artworkFile = name
            }
            if let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2),
               let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 132300) {
                buffer.frameLength = 132300
                for channel in 0..<2 {
                    for frame in 0..<132300 { buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 440 * 2 * .pi / 44100)) * 0.005 }
                }
                if let file = try? AVAudioFile(forWriting: url(for: fixture), settings: format.settings) { try? file.write(from: buffer) }
                songs = [fixture]
            }
        } else if scanOnStart && !FileManager.default.fileExists(atPath: indexURL.path) { Task { await scan() } }
        #else
        if scanOnStart && !FileManager.default.fileExists(atPath: indexURL.path) { Task { await scan() } }
        #endif
    }

    func url(for song: Song) -> URL { musicDirectory.appendingPathComponent(song.id) }
    func save() {
        if let data = try? JSONEncoder().encode(songs) { try? data.write(to: indexURL, options: .atomic) }
        if let data = try? JSONEncoder().encode(folders) { try? data.write(to: foldersURL, options: .atomic) }
        if let data = try? JSONEncoder().encode(artistPhotos) { try? data.write(to: photosURL, options: .atomic) }
    }
    func savePhotoAttempts() {
        if let data = try? JSONEncoder().encode(photoAttempts) { try? data.write(to: photoAttemptsURL, options: .atomic) }
    }
    func update(_ song: Song) {
        guard let i = songs.firstIndex(where: { $0.id == song.id }) else { return }
        songs[i] = song
        save()
    }
    func markPlayed(_ song: Song) {
        guard let i = songs.firstIndex(where: { $0.id == song.id }) else { return }
        songs[i].playCount += 1
        save()
    }

    func scan() async {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: musicDirectory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        let urls = (enumerator.allObjects as? [URL] ?? []).filter { Self.extensions.contains($0.pathExtension.lowercased()) }
        let old = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        var result: [Song] = []
        for url in urls {
            guard let relative = MediaFiles.relativePath(of: url, under: musicDirectory),
                  (try? MediaFiles.validate(url)) != nil else { continue }
            if let existing = old[relative], existing.metadataVerified != nil { result.append(existing); continue }
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
            let items = (try? await asset.load(.commonMetadata)) ?? []
            func value(_ key: AVMetadataKey) -> String? {
                items.first(where: { $0.commonKey?.rawValue == key.rawValue })?.stringValue
            }
            let name = url.deletingPathExtension().lastPathComponent
            let parts = name.components(separatedBy: " - ")
            let title = value(.commonKeyTitle) ?? (parts.count >= 2 ? parts.dropFirst().joined(separator: " - ") : name)
            let artist = value(.commonKeyArtist) ?? (parts.count >= 2 ? parts[0] : "Artista desconocido")
            var imported = Song(id: relative, title: title, artist: artist, album: value(.commonKeyAlbumName) ?? "Sin álbum", duration: duration.isFinite ? duration : 0, isVideo: ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()))
            imported.metadataVerified = value(.commonKeyTitle) != nil && value(.commonKeyArtist) != nil
            if var existing = old[relative] { existing.metadataVerified = imported.metadataVerified; imported = existing }
            result.append(imported)
        }
        missingArtwork.removeAll()
        songs = result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        save()
    }

    func importFiles(_ urls: [URL]) async {
        var failures = 0
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard Self.extensions.contains(url.pathExtension.lowercased()) else { failures += 1; continue }
            let target = uniqueFile(for: url.lastPathComponent)
            do { try await MediaFiles.copyForImport(from: url, to: target) } catch { failures += 1 }
        }
        await scan()
        message = failures == 0 ? "Importación terminada" : "No se pudieron copiar \(failures) archivos"
    }
    func importFolder(_ source: URL) async {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        do {
            guard (try source.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
                throw ServiceError(message: "Selecciona una carpeta de música.")
            }
            let existing = folders.first { $0.sourcePath == source.standardizedFileURL.path }
            let name = existing?.targetName ?? uniqueFolderName(source.lastPathComponent)
            let bookmark = try source.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let count = try await copyFolder(source, to: musicDirectory.appendingPathComponent(name, isDirectory: true))
            if existing == nil {
                folders.append(MusicFolder(name: source.lastPathComponent, sourcePath: source.standardizedFileURL.path,
                                           targetName: name, bookmark: bookmark))
            }
            await scan()
            message = "Carpeta importada: \(count) archivos nuevos o actualizados."
        } catch { message = "No se pudo importar la carpeta: \(error.localizedDescription)" }
    }

    func rescanFolder(_ folder: MusicFolder) async {
        do {
            var stale = false
            let source = try URL(resolvingBookmarkData: folder.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            guard access || source.isFileURL && FileManager.default.isReadableFile(atPath: source.path) else {
                throw ServiceError(message: "El acceso caducó. Vuelve a añadir la carpeta desde Archivos.")
            }
            let count = try await copyFolder(source, to: musicDirectory.appendingPathComponent(folder.targetName, isDirectory: true))
            if stale, let index = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[index].bookmark = try source.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            await scan()
            message = "Carpeta actualizada: \(count) archivos nuevos o modificados."
        } catch { message = "No se pudo actualizar \(folder.name): \(error.localizedDescription)" }
    }

    func removeFolder(_ folder: MusicFolder) async {
        do {
            let destination = musicDirectory.appendingPathComponent(folder.targetName, isDirectory: true)
            try FileManager.default.removeItem(at: destination)
            folders.removeAll { $0.id == folder.id }
            await scan()
            message = "Se quitó \(folder.name) de la biblioteca. La carpeta original sigue en Archivos."
        } catch { message = "No se pudo quitar la carpeta: \(error.localizedDescription)" }
    }

    private func uniqueFolderName(_ name: String) -> String {
        let safe = name.isEmpty ? "Música importada" : name
        var candidate = safe
        var suffix = 2
        while FileManager.default.fileExists(atPath: musicDirectory.appendingPathComponent(candidate).path) {
            candidate = "\(safe) (\(suffix))"; suffix += 1
        }
        return candidate
    }

    private func copyFolder(_ source: URL, to destination: URL) async throws -> Int {
        guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                               options: [.skipsHiddenFiles]) else {
            throw ServiceError(message: "No se puede leer esta carpeta desde Archivos.")
        }
        let files = (enumerator.allObjects as? [URL] ?? []).filter {
            Self.extensions.contains($0.pathExtension.lowercased()) || $0.pathExtension.lowercased() == "lrc"
        }
        var count = 0
        var failures = 0
        for file in files {
            guard let relative = MediaFiles.relativePath(of: file, under: source) else { continue }
            let target = destination.appendingPathComponent(relative)
            do {
                let sourceSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
                let targetSize = try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if sourceSize == targetSize, targetSize != nil { continue }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try await MediaFiles.copyForImport(from: file, to: target)
                count += 1
            } catch { failures += 1 }
        }
        if failures > 0 { throw ServiceError(message: "\(failures) archivos no pudieron copiarse. Revisa que estén descargados en Archivos.") }
        return count
    }

    private func uniqueFile(for filename: String) -> URL {
        let original = musicDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: original.path) else { return original }
        let stem = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        var n = 2
        while true {
            let candidate = musicDirectory.appendingPathComponent("\(stem) (\(n)).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    func setArtwork(_ imageData: Data, for song: Song) throws {
        let file = "art-\(UUID().uuidString).jpg"
        try imageData.write(to: documents.appendingPathComponent(file), options: .atomic)
        artworkCache.removeObject(forKey: "song:\(song.id)" as NSString)
        missingArtwork.remove("song:\(song.id)")
        var copy = song; copy.artworkFile = file; update(copy)
    }
    func setArtistPhoto(_ imageData: Data, for artist: String) throws {
        let file = "artist-\(UUID().uuidString).jpg"
        try imageData.write(to: documents.appendingPathComponent(file), options: .atomic)
        artworkCache.removeObject(forKey: "artist:\(artist)" as NSString)
        missingArtwork.remove("artist:\(artist)")
        artistPhotos[artist] = file; save()
    }
    func image(for song: Song) -> UIImage? {
        let key = "song:\(song.id)" as NSString
        if let image = artworkCache.object(forKey: key) { return image }
        if missingArtwork.contains(key as String) { return nil }
        let data: Data?
        if let file = song.artworkFile { data = try? Data(contentsOf: documents.appendingPathComponent(file)) }
        else {
            let asset = AVURLAsset(url: url(for: song))
            data = asset.commonMetadata.first(where: { $0.commonKey?.rawValue == AVMetadataKey.commonKeyArtwork.rawValue })?.dataValue
        }
        guard let data, let image = Self.thumbnail(data) else { missingArtwork.insert(key as String); return nil }
        artworkCache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
    func artistImage(_ artist: String) -> UIImage? {
        guard let file = artistPhotos[artist] else { return nil }
        let key = "artist:\(artist)" as NSString
        if let image = artworkCache.object(forKey: key) { return image }
        guard let data = try? Data(contentsOf: documents.appendingPathComponent(file)),
              let image = Self.thumbnail(data) else { return nil }
        artworkCache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
    static func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 900
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    func localLyrics(for song: Song) -> String? {
        if let file = lyricFile(for: song), let text = try? String(contentsOf: file, encoding: .utf8) { return text }
        if let lyrics = song.lyrics { return lyrics.isEmpty ? nil : lyrics }
        let lrc = url(for: song).deletingPathExtension().appendingPathExtension("lrc")
        return try? String(contentsOf: lrc, encoding: .utf8)
    }
}
