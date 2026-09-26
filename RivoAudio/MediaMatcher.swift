import Foundation

struct MediaMatch: Identifiable {
    let song: Song
    let score: Double
    let automatic: Bool
    var id: String { song.id }
}
enum MediaMatcher {
    static func title(_ text: String) -> String {
        var result = OnlineSupport.normalized(text)
        for phrase in ["official music video", "official lyric video", "official video", "official audio", "music video", "video oficial", "audio oficial", "official visualizer", "lyric video", "lyrics", "1080p", "720p", "4k", "hd"] {
            result = result.replacingOccurrences(of: "\\b\(phrase)\\b", with: " ", options: .regularExpression)
        }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func score(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return lhs.isEmpty ? 0 : 1 }
        let a = Set(lhs.split(separator: " ")); let b = Set(rhs.split(separator: " "))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let tokens = Double(a.intersection(b).count) / Double(a.union(b).count)
        let left = Array(lhs.prefix(300)), right = Array(rhs.prefix(300))
        var previous = Array(0...right.count)
        for (i, character) in left.enumerated() {
            var row = [i + 1]
            for (j, other) in right.enumerated() {
                row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (character == other ? 0 : 1)))
            }
            previous = row
        }
        let spelling = 1 - Double(previous[right.count]) / Double(max(left.count, right.count))
        return max(tokens, spelling)
    }
    static func candidates(for song: Song, in library: [Song]) -> [MediaMatch] {
        let sourceTitle = title(song.title)
        let sourceArtist = OnlineSupport.normalized(song.artist)
        return library.filter { $0.isVideo != song.isVideo }.compactMap { candidate in
            let candidateTitle = title(candidate.title)
            // Keep remix/live/acoustic versions distinct.
            let variants: Set<String> = ["live", "remix", "acoustic", "instrumental", "karaoke", "sped", "slowed"]
            let sourceVariants = Set(sourceTitle.split(separator: " ").map(String.init)).intersection(variants)
            let targetVariants = Set(candidateTitle.split(separator: " ").map(String.init)).intersection(variants)
            guard sourceVariants == targetVariants else { return nil }
            let artist = OnlineSupport.normalized(candidate.artist)
            let known = !sourceArtist.isEmpty && !artist.isEmpty && sourceArtist != "artista desconocido" && artist != "artista desconocido"
            if known && sourceArtist != artist { return nil }
            let similarity = score(sourceTitle, candidateTitle)
            let fileSimilarity = score(title(URL(fileURLWithPath: song.id).deletingPathExtension().lastPathComponent), title(URL(fileURLWithPath: candidate.id).deletingPathExtension().lastPathComponent))
            let best = max(similarity, fileSimilarity)
            guard best >= 0.65 else { return nil }
            let closeDuration = song.duration > 0 && candidate.duration > 0 && abs(song.duration - candidate.duration) <= 15
            return MediaMatch(song: candidate, score: best + (known ? 0.15 : 0) + (closeDuration ? 0.05 : 0), automatic: known && similarity == 1 && closeDuration)
        }.sorted { $0.score == $1.score ? $0.song.id < $1.song.id : $0.score > $1.score }
    }
    static func automaticMatch(_ matches: [MediaMatch]) -> Song? {
        guard let first = matches.first, first.automatic else { return nil }
        guard matches.count == 1 || first.score - matches[1].score > 0.08 else { return nil }
        return first.song
    }
}
