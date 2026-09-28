import Foundation
import CryptoKit

struct LyricRecord: Codable {
    var file: String
    var source: String
    var updated: Date
}

extension MusicLibrary {
    var lyricsDirectory: URL { documents.appendingPathComponent("Lyrics", isDirectory: true) }
    private var lyricIndexURL: URL { lyricsDirectory.appendingPathComponent("index.json") }
    func lyricRecords() -> [String: LyricRecord] {
        guard let data = try? Data(contentsOf: lyricIndexURL) else { return [:] }
        return (try? JSONDecoder().decode([String: LyricRecord].self, from: data)) ?? [:]
    }
    func lyricFile(for song: Song) -> URL? {
        guard let record = lyricRecords()[song.id] else { return nil }
        return lyricsDirectory.appendingPathComponent(record.file)
    }
    func saveLyrics(_ text: String, for song: Song, source: String) throws {
        try FileManager.default.createDirectory(at: lyricsDirectory, withIntermediateDirectories: true)
        let name = SHA256.hash(data: Data(song.id.utf8)).map { String(format: "%02x", $0) }.joined() + ".lrc"
        try text.write(to: lyricsDirectory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        var records = lyricRecords()
        records[song.id] = LyricRecord(file: name, source: source, updated: Date())
        try JSONEncoder().encode(records).write(to: lyricIndexURL, options: .atomic)
        var copy = songs.first(where: { $0.id == song.id }) ?? song
        copy.lyrics = nil
        update(copy)
        objectWillChange.send()
    }
    func deleteLyrics(for song: Song) throws {
        var records = lyricRecords()
        if let record = records[song.id] {
            let file = lyricsDirectory.appendingPathComponent(record.file)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
        records.removeValue(forKey: song.id)
        try FileManager.default.createDirectory(at: lyricsDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: lyricIndexURL, options: .atomic)
        // Empty string suppresses re-import of a legacy sidecar after explicit deletion.
        var copy = songs.first(where: { $0.id == song.id }) ?? song
        copy.lyrics = ""
        update(copy)
    }
    func migrateLyrics() {
        for song in songs where lyricFile(for: song) == nil {
            let legacy = song.lyrics ?? (try? String(contentsOf: url(for: song).deletingPathExtension().appendingPathExtension("lrc"), encoding: .utf8))
            if let legacy, !legacy.isEmpty { try? saveLyrics(legacy, for: song, source: "Migración local") }
        }
    }
    func autoLyrics(for song: Song) async {
        guard UserDefaults.standard.object(forKey: "lyrics.auto") == nil || UserDefaults.standard.bool(forKey: "lyrics.auto"),
              lyricFile(for: song) == nil, localLyrics(for: song)?.isEmpty != false, song.lyrics != "" else { return }
        let key = "lyrics.attempt." + song.id
        if let date = UserDefaults.standard.object(forKey: key) as? Date, Date().timeIntervalSince(date) < 86400 { return }
        UserDefaults.standard.set(Date(), forKey: key)
        do {
            if let result = try await LyricSearch.fetch(song: song), !Task.isCancelled,
               let current = songs.first(where: { $0.id == song.id }), current.lyrics != "", lyricFile(for: current) == nil, localLyrics(for: current)?.isEmpty != false {
                try saveLyrics(result, for: current, source: "LRCLIB · automática")
            }
        } catch { /* Retry only on a later day or an explicit manual search. */ }
    }
}
