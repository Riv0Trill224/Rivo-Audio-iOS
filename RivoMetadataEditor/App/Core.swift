import Foundation

enum Advisory: Int, Codable, CaseIterable, Identifiable, Sendable {
    case none = 0, explicit = 1, clean = 2
    var id: Int { rawValue }
    var label: String {
        switch self { case .none: return "Sin clasificar"; case .explicit: return "Explícito"; case .clean: return "Versión limpia" }
    }
}

struct Tags: Codable, Equatable, Sendable {
    var fields: [String: String] = [:]
    subscript(_ key: String) -> String {
        get { fields[key] ?? "" }
        set { fields[key] = newValue }
    }
    var advisory: Advisory {
        get { Advisory(rawValue: Int(self["ITUNESADVISORY"]) ?? 0) ?? .none }
        set { self["ITUNESADVISORY"] = String(newValue.rawValue) }
    }
    func changes(from original: Tags) -> [String: String] {
        fields.filter { original[$0.key] != $0.value }
    }
}

struct MusicFolder: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var bookmark: Data
}
struct FileStamp: Codable, Equatable, Sendable {
    let size: Int64
    let modified: Date
}
struct Track: Identifiable, Codable, Sendable {
    var id: String { folderID.uuidString + "/" + relativePath }
    let folderID: UUID
    let relativePath: String
    var tags: Tags
    var duration: Double
    var bitrate: Int
    var sampleRate: Int
    var stamp: FileStamp
    var hasLRC: Bool
    var hasArtwork: Bool = false
    var error: String?
    var filename: String { (relativePath as NSString).lastPathComponent }
    var title: String { tags["TITLE"].isEmpty ? (filename as NSString).deletingPathExtension : tags["TITLE"] }
    var artist: String { tags["ARTIST"] }
    var album: String { tags["ALBUM"] }
}

struct LyricsCandidate: Identifiable, Codable, Sendable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: Double
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
    var isSynced: Bool { syncedLyrics.map { LRC.hasTimestamps($0) } ?? false }
}
struct ReviewItem: Identifiable, Codable, Sendable {
    var id: String { track.id }
    var track: Track
    var candidates: [LyricsCandidate]
    var reason: String
}
struct HistoryEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let folderID: UUID
    let relativePath: String
    let backupName: String?
    let afterHash: String
    let description: String
}
struct JobProgress: Sendable {
    var completed = 0
    var total = 0
    var found = 0
    var skipped = 0
    var pending = 0
    var failed = 0
    var current = ""
    var recentSeconds: [Double] = []
    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    var eta: String {
        guard !recentSeconds.isEmpty, completed < total else { return completed == total && total > 0 ? "Terminado" : "Calculando…" }
        let seconds = Int(recentSeconds.reduce(0, +) / Double(recentSeconds.count) * Double(total - completed))
        return seconds >= 60 ? "\(seconds / 60) min \(seconds % 60) s" : "\(seconds) s"
    }
    mutating func finish(seconds: Double) {
        completed += 1
        recentSeconds.append(seconds)
        recentSeconds = Array(recentSeconds.suffix(12))
    }
}

enum Match {
    // Do not strip version words: live, remix, instrumental, clean and explicit matter.
    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Set(normalize(a).split(separator: " "))
        let y = Set(normalize(b).split(separator: " "))
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        return Double(x.intersection(y).count) / Double(x.union(y).count)
    }
    static func score(_ c: LyricsCandidate, _ t: Track) -> Double {
        let title = similarity(c.trackName, t.title), artist = similarity(c.artistName, t.artist)
        let album = similarity(c.albumName, t.album)
        let time = t.duration > 0 && abs(c.duration - t.duration) <= 2 ? 1.0 : 0.0
        return title * 0.45 + artist * 0.30 + time * 0.20 + album * 0.05
    }
    static func automatic(_ candidates: [LyricsCandidate], track: Track) -> LyricsCandidate? {
        guard !track.tags["TITLE"].isEmpty, !track.artist.isEmpty, track.duration > 0 else { return nil }
        let safe = candidates.filter {
            $0.isSynced && !$0.instrumental && normalize($0.trackName) == normalize(track.title)
            && normalize($0.artistName) == normalize(track.artist) && abs($0.duration - track.duration) <= 2
            && (track.album.isEmpty || normalize($0.albumName) == normalize(track.album))
        }
        // Different synchronized lyrics for the same song are an ambiguity, not an auto-match.
        let texts = Set(safe.compactMap(\.syncedLyrics))
        return texts.count == 1 ? safe.first : nil
    }
}

enum LRC {
    static let timestampPattern = #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
    static func hasTimestamps(_ text: String) -> Bool {
        (try? NSRegularExpression(pattern: timestampPattern))?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
    static func shift(_ text: String, milliseconds: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: timestampPattern) else { return text }
        var output = text
        // Keep metadata headers and [offset:] untouched; shift every timestamp, including multi-time lines.
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            func group(_ n: Int) -> String { Range(match.range(at: n), in: text).map { String(text[$0]) } ?? "" }
            let fraction = group(3)
            let ms = Int(fraction.padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
            let total = max(0, (Int(group(1)) ?? 0) * 60_000 + (Int(group(2)) ?? 0) * 1000 + ms + milliseconds)
            if let range = Range(match.range, in: output) {
                output.replaceSubrange(range, with: String(format: "[%02d:%02d.%03d]", total / 60_000, (total / 1000) % 60, total % 1000))
            }
        }
        return output
    }
    static func filename(audio: String) -> String { (audio as NSString).deletingPathExtension + ".lrc" }
    static func validate(_ text: String) throws {
        guard text.utf8.count <= 2_000_000, hasTimestamps(text) else {
            throw RivoError.message("La letra no contiene tiempos LRC válidos o es demasiado grande.")
        }
        let regex = try NSRegularExpression(pattern: timestampPattern)
        for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let r = Range(m.range(at: 2), in: text), (Int(text[r]) ?? 60) >= 60 {
                throw RivoError.message("Un tiempo LRC tiene segundos mayores a 59.")
            }
        }
    }
}
enum RivoError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let s): return s } }
}
