import Foundation
import AVFoundation
import UIKit
import Combine

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

@MainActor final class MusicLibrary: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published var message: String? = nil
    @Published var artistPhotos: [String: String] = [:]
    @Published var photoCredits: [String: ArtistPhotoCredit] = [:]
    @Published var photoStatus: [String: String] = [:]
    var photoRequests: Set<String> = []
    var photoAttempts: [String: Date] = [:]
    let documents: URL
    var musicDirectory: URL { documents.appendingPathComponent("Music", isDirectory: true) }
    private var indexURL: URL { documents.appendingPathComponent("library.json") }
    private var photosURL: URL { documents.appendingPathComponent("artistPhotos.json") }
    static let extensions: Set<String> = ["mp3", "m4a", "aac", "alac", "wav", "aif", "aiff", "caf", "flac", "mp4", "m4v", "mov"]

    init(documents: URL? = nil, scanOnStart: Bool = true) {
        self.documents = documents ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL), let value = try? JSONDecoder().decode([Song].self, from: data) { songs = value }
        if let data = try? Data(contentsOf: photosURL), let value = try? JSONDecoder().decode([String: String].self, from: data) { artistPhotos = value }
        if let data = try? Data(contentsOf: self.documents.appendingPathComponent("artistPhotoCredits.json")),
           let saved = try? JSONDecoder().decode([String: ArtistPhotoCredit].self, from: data) { photoCredits = saved }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-fixture") {
            let fixture = Song(id: "Neon.wav", title: "Neon Nights", artist: "Rivo Sessions", album: "Prueba de interfaz", duration: 3)
            if let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2),
               let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 132300) {
                buffer.frameLength = 132300
                for channel in 0..<2 {
                    for frame in 0..<132300 { buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 440 * 2 * .pi / 44100)) * 0.005 }
                }
                if let file = try? AVAudioFile(forWriting: url(for: fixture), settings: format.settings) { try? file.write(from: buffer) }
                songs = [fixture]
            }
        } else if scanOnStart { Task { await scan() } }
        #else
        if scanOnStart { Task { await scan() } }
        #endif
    }

    func url(for song: Song) -> URL { musicDirectory.appendingPathComponent(song.id) }
    func save() {
        if let data = try? JSONEncoder().encode(songs) { try? data.write(to: indexURL, options: .atomic) }
        if let data = try? JSONEncoder().encode(artistPhotos) { try? data.write(to: photosURL, options: .atomic) }
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
        var copy = song; copy.artworkFile = file; update(copy)
    }
    func setArtistPhoto(_ imageData: Data, for artist: String) throws {
        let file = "artist-\(UUID().uuidString).jpg"
        try imageData.write(to: documents.appendingPathComponent(file), options: .atomic)
        artistPhotos[artist] = file; save()
    }
    func image(for song: Song) -> UIImage? {
        if let file = song.artworkFile, let image = UIImage(contentsOfFile: documents.appendingPathComponent(file).path) { return image }
        let asset = AVURLAsset(url: url(for: song))
        guard let item = asset.commonMetadata.first(where: { $0.commonKey?.rawValue == AVMetadataKey.commonKeyArtwork.rawValue }), let data = item.dataValue else { return nil }
        return UIImage(data: data)
    }
    func artistImage(_ artist: String) -> UIImage? {
        guard let file = artistPhotos[artist] else { return nil }
        return UIImage(contentsOfFile: documents.appendingPathComponent(file).path)
    }
    func localLyrics(for song: Song) -> String? {
        if let lyrics = song.lyrics, !lyrics.isEmpty { return lyrics }
        let lrc = url(for: song).deletingPathExtension().appendingPathExtension("lrc")
        return try? String(contentsOf: lrc, encoding: .utf8)
    }
}
