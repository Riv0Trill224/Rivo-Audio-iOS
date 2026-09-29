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
    var sourceFolderID: UUID? = nil
    var sourceRelativePath: String? = nil
    var albumArtist: String? = nil
    var trackNumber: Int? = nil
    var discNumber: Int? = nil
}

struct MusicFolder: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var sourcePath: String
    var targetName: String
    var bookmark: Data
    var linked: Bool? = nil
    var singleFile: Bool? = nil
}

@MainActor final class MusicLibrary: ObservableObject {
    @Published var songs: [Song] = []
    @Published var folders: [MusicFolder] = []
    @Published var message: String? = nil
    @Published var extras = LibraryExtras()
    @Published var scanning = false
    let scanProgress = ScanProgress()
    var pendingDetails: [String: TrackDetails] = [:]
    @Published var artistPhotos: [String: String] = [:]
    @Published var photoCredits: [String: ArtistPhotoCredit] = [:]
    @Published var photoStatus: [String: String] = [:]
    var photoRequests: Set<String> = []
    var scopedSources: [UUID: ScopedSource] = [:]
    var lyricIndexCache: [String: LyricRecord]? = nil
    var artworkTasks: [String: Task<UIImage?, Never>] = [:]
    var photoAttempts: [String: Date] = [:]
    let documents: URL
    var musicDirectory: URL { documents.appendingPathComponent("Music", isDirectory: true) }
    private var indexURL: URL { documents.appendingPathComponent("library.json") }
    private var foldersURL: URL { documents.appendingPathComponent("musicFolders.json") }
    private var photosURL: URL { documents.appendingPathComponent("artistPhotos.json") }
    private var photoAttemptsURL: URL { documents.appendingPathComponent("artistPhotoAttempts.json") }
    private let artworkCache = NSCache<NSString, UIImage>()
    private var missingArtwork = Set<String>()
    var missingArtworkIDs = Set<String>()
    nonisolated static let extensions: Set<String> = ["mp3", "m4a", "aac", "alac", "wav", "aif", "aiff", "caf", "flac", "mp4", "m4v", "mov"]

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
        loadExtras()
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
                if ProcessInfo.processInfo.arguments.contains("--ui-video-fixture"), let video = Bundle.main.url(forResource: "UITestVideo", withExtension: "mp4") {
                    let target = musicDirectory.appendingPathComponent("Neon.mp4")
                    try? FileManager.default.removeItem(at: target)
                    try? FileManager.default.copyItem(at: video, to: target)
                    songs = [Song(id: "Neon.mp4", title: "Video de prueba", artist: "Rivo", album: "Prueba", duration: 60, isVideo: true)]
                }
            }
        } else if scanOnStart && !FileManager.default.fileExists(atPath: indexURL.path) { Task { await scan() } }
        #else
        if scanOnStart && !FileManager.default.fileExists(atPath: indexURL.path) { Task { await scan() } }
        #endif
    }

    func url(for song: Song) -> URL {
        if song.sourceFolderID != nil { return (try? access(for: song).url) ?? documents.appendingPathComponent("Unavailable/" + song.id) }
        return musicDirectory.appendingPathComponent(song.id)
    }
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

    func scan(force: Bool = false) async {
        let owner = !scanning
        if owner { scanning = true }
        defer { if owner { scanning = false; scanProgress.finish() } }
        scanProgress.set("Leyendo carpetas locales")
        let linked = songs.filter { $0.sourceFolderID != nil }
        let linkedIDs = Set(linked.map(\.id))
        let root = musicDirectory
        let files = await Task.detached(priority: .utility) {
            (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?.allObjects as? [URL] ?? []).filter { Self.extensions.contains($0.pathExtension.lowercased()) }
        }.value
        let previous = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        var result = linked
        for (offset, url) in files.enumerated() {
            if offset % 20 == 0 { scanProgress.set("Leyendo archivos locales", done: offset, total: files.count); await Task.yield() }
            guard let id = MediaFiles.relativePath(of: url, under: musicDirectory), !linkedIDs.contains(id) else { continue }
            let old = previous[id]
            if !force, let old, old.albumArtist != nil { result.append(old); continue }
            if let song = try? await readSong(url, id: id, old: old) { result.append(song) }
        }
        songs = result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        do { try await persistScan(); scanProgress.set("Lectura local completada", done: files.count, total: files.count) }
        catch { message = error.localizedDescription }
    }
    func importFiles(_ urls: [URL]) async {
        guard !scanning else { return }; scanning = true; defer { scanning = false; scanProgress.finish() }
        var failures = 0
        for source in urls {
            do { try await linkSource(source, singleFile: true) } catch { failures += 1 }
        }
        message = failures == 0 ? "Archivos vinculados sin copiar audio ni video." : "No se pudieron vincular \(failures) archivos. Revisa su acceso en Archivos."
    }
    func importFolder(_ source: URL) async {
        guard !scanning else { return }; scanning = true; defer { scanning = false; scanProgress.finish() }
        do { try await linkSource(source, singleFile: false); message = "Carpeta vinculada sin copiar audio ni video." }
        catch { message = "No se pudo vincular: \(error.localizedDescription)" }
    }
    func rescanFolder(_ folder: MusicFolder) async {
        let owner = !scanning; if owner { scanning = true }; defer { if owner { scanning = false; scanProgress.finish() } }
        do {
            let source = try resolve(folder)
            try await indexSource(folder, source: source)
            message = "Carpeta actualizada sin copiar archivos."
        } catch { message = "No se pudo acceder a \(folder.name). Vuelve a vincularla en Ajustes. \(error.localizedDescription)" }
    }
    func removeFolder(_ folder: MusicFolder) async {
        guard !scanning else { return }
        songs.removeAll { $0.sourceFolderID == folder.id || ($0.sourceFolderID == nil && $0.id.hasPrefix(folder.targetName + "/")) }
        folders.removeAll { $0.id == folder.id }; scopedSources.removeValue(forKey: folder.id)
        save(); message = "Vínculo quitado. Los archivos originales se conservan."
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
        else { data = try? Data(contentsOf: artworkURL(song)) }
        guard let data, let image = Self.thumbnail(data) else { return nil }
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
    nonisolated static func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 480
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
