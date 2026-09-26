import Foundation

struct LyricLine: Identifiable {
    let id: Int
    let time: TimeInterval
    let text: String
}

enum LRC {
    static func parse(_ source: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        for raw in source.components(separatedBy: .newlines) {
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            let matches = regex.matches(in: raw, range: range)
            guard let last = matches.last, let end = Range(last.range, in: raw) else { continue }
            let text = String(raw[end.upperBound...]).trimmingCharacters(in: .whitespaces)
            for match in matches {
                func capture(_ index: Int) -> String {
                    guard let range = Range(match.range(at: index), in: raw) else { return "0" }
                    return String(raw[range])
                }
                let fraction = capture(3)
                let divisor = pow(10.0, Double(fraction.count))
                let time = Double(capture(1))! * 60 + Double(capture(2))! + (Double(fraction) ?? 0) / divisor
                lines.append(LyricLine(id: lines.count, time: time, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}

private struct LyricResult: Decodable {
    let trackName: String
    let artistName: String
    let syncedLyrics: String?
    let plainLyrics: String?
}

enum LyricSearch {
    static func fetch(song: Song) async throws -> String? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [URLQueryItem(name: "track_name", value: song.title), URLQueryItem(name: "artist_name", value: song.artist)]
        var request = URLRequest(url: components.url!)
        request.setValue("RivoAudio-iOS/0.1 (personal local player)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let candidates = try JSONDecoder().decode([LyricResult].self, from: data)
        let normalizedTitle = normalize(song.title)
        let normalizedArtist = normalize(song.artist)
        let best = candidates.filter { candidate in
            let title = normalize(candidate.trackName)
            let artist = normalize(candidate.artistName)
            return (title == normalizedTitle || title.contains(normalizedTitle) || normalizedTitle.contains(title)) &&
                   (artist == normalizedArtist || artist.contains(normalizedArtist) || normalizedArtist.contains(artist))
        }.first(where: { $0.syncedLyrics != nil })
        return best?.syncedLyrics
    }
    static func suggested(song: Song) async throws -> [(title: String, artist: String, lyrics: String)] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [URLQueryItem(name: "q", value: song.title)]
        var request = URLRequest(url: components.url!)
        request.setValue("RivoAudio-iOS/0.1 (personal local player)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let results = try JSONDecoder().decode([LyricResult].self, from: data)
        return results.compactMap { candidate in
            guard let lyrics = candidate.syncedLyrics else { return nil }
            return (candidate.trackName, candidate.artistName, lyrics)
        }
    }
    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"\([^)]*\)|\[[^]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
