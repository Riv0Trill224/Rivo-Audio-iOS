import Foundation
struct MediaMatch: Identifiable {
    let song: Song
    let score: Double
    let automatic: Bool
    var id: String { song.id }
}
enum MediaMatcher {
    static func basename(_ song: Song) -> String { URL(fileURLWithPath: song.id).deletingPathExtension().lastPathComponent }
    static func candidates(for song: Song, in library: [Song]) -> [MediaMatch] {
        let name = basename(song)
        guard !name.isEmpty else { return [] }
        let found = library.filter { $0.isVideo != song.isVideo && basename($0) == name }
        return found.map { MediaMatch(song: $0, score: 1, automatic: found.count == 1) }.sorted { $0.id < $1.id }
    }
    static func automaticMatch(_ matches: [MediaMatch]) -> Song? { matches.count == 1 ? matches[0].song : nil }
}
