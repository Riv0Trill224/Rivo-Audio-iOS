import Foundation
import CryptoKit
import UIKit
import ImageIO

actor MusicServices {
    static let shared = MusicServices()
    private var nextRequest: [String: Date] = [:]
    private let session: URLSession
    private let fm = FileManager.default
    private var cacheRoot: URL {
        fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("RivoAPI", isDirectory: true)
    }
    init() {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 25; c.timeoutIntervalForResource = 45
        c.httpAdditionalHeaders = ["User-Agent": "RivoMetadataEditor/0.2.0 (https://github.com/Riv0Trill224)"]
        session = URLSession(configuration: c)
    }
    private func request(_ url: URL, cache: Bool = true, maxBytes: Int = 4_000_000, bearer: String? = nil) async throws -> Data {
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let cached = cacheRoot.appendingPathComponent(key)
        if cache, let a = try? fm.attributesOfItem(atPath: cached.path), let date = a[.modificationDate] as? Date,
           Date().timeIntervalSince(date) < 7 * 86400, let data = try? Data(contentsOf: cached) { return data }
        let host = url.host ?? ""
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let earliest = max(Date(), nextRequest[host] ?? .distantPast)
            nextRequest[host] = earliest.addingTimeInterval(host == "musicbrainz.org" ? 1.1 : 0.4)
            let delay = earliest.timeIntervalSinceNow
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            var request = URLRequest(url: url)
            if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw RivoError.message("Respuesta de red inválida.") }
            if [429, 503].contains(http.statusCode), attempt < 2 {
                let delay = max(1, min(30, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? pow(2, Double(attempt + 1))))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)); continue
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw RivoError.message("\(host): acceso rechazado. Revisa el token de Genius en Ajustes si estabas usando ese motor.")
            }
            if http.statusCode == 404 { throw ServiceError.notFound }
            guard (200..<300).contains(http.statusCode) else { throw RivoError.message("\(host) respondió HTTP \(http.statusCode). Intenta de nuevo.") }
            guard data.count <= maxBytes else { throw RivoError.message("La respuesta supera el tamaño admitido.") }
            if cache { try? fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true); try? data.write(to: cached, options: .atomic) }
            return data
        }
        throw RivoError.message("Se agotaron los reintentos de red.")
    }
    private func url(_ base: String, _ values: [String: String]) throws -> URL {
        guard var c = URLComponents(string: base) else { throw RivoError.message("Dirección de servicio inválida.") }
        c.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let u = c.url else { throw RivoError.message("No se pudo preparar la búsqueda.") }; return u
    }
    func lyrics(_ track: Track) async throws -> [LyricsCandidate] {
        var candidates: [LyricsCandidate] = []
        if !track.tags["TITLE"].isEmpty, !track.artist.isEmpty, track.duration > 0 {
            let u = try url("https://lrclib.net/api/get", ["track_name": track.title, "artist_name": track.artist,
                       "album_name": track.album, "duration": String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), track.duration)])
            do { candidates.append(try JSONDecoder().decode(LyricsCandidate.self, from: await request(u))) }
            catch ServiceError.notFound { /* Search fallback below. */ }
        }
        if Match.automatic(candidates, track: track) != nil { return candidates }
        var params = ["track_name": track.title]
        if !track.artist.isEmpty { params["artist_name"] = track.artist }
        let u = try url("https://lrclib.net/api/search", params)
        candidates += try JSONDecoder().decode([LyricsCandidate].self, from: await request(u))
        if candidates.isEmpty {
            let broad = try url("https://lrclib.net/api/search", ["q": [track.artist, track.title].filter { !$0.isEmpty }.joined(separator: " ")])
            candidates += try JSONDecoder().decode([LyricsCandidate].self, from: await request(broad))
        }
        var ids: Set<Int> = []
        return candidates.filter { ids.insert($0.id).inserted }.sorted { Match.score($0, track) > Match.score($1, track) }
    }
    func genius(title: String, artist: String) async throws -> [GeniusCandidate] {
        let token = GeniusCredentials.read()
        guard !token.isEmpty else { throw RivoError.message("Para buscar Genius dentro de la app, configura tu token en Ajustes. También puedes consultar su web sin token.") }
        let u = try url("https://api.genius.com/search", ["q": [artist, title].filter { !$0.isEmpty }.joined(separator: " ")])
        let response = try JSONDecoder().decode(GeniusSearch.self, from: await request(u, cache: false, bearer: token))
        return response.songs.sorted {
            let left = Match.similarity($0.title, title) + Match.similarity($0.artist, artist)
            let right = Match.similarity($1.title, title) + Match.similarity($1.artist, artist)
            return left > right
        }
    }
    private func escapeLucene(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    func metadata(_ track: Track) async throws -> [MetadataCandidate] {
        var query = "recording:\"\(escapeLucene(track.title))\""
        if !track.artist.isEmpty { query += " AND artist:\"\(escapeLucene(track.artist))\"" }
        let u = try url("https://musicbrainz.org/ws/2/recording", ["query": query, "fmt": "json", "limit": "15"])
        let response = try JSONDecoder().decode(MBSearch.self, from: await request(u))
        return (response.recordings ?? []).flatMap { rec in
            let artist = (rec.artistCredit ?? []).map { ($0.name ?? $0.artist?.name ?? "") + ($0.joinphrase ?? "") }.joined()
            let releases = rec.releases ?? []
            if releases.isEmpty {
                return [MetadataCandidate(id: rec.id, title: rec.title, artist: artist, album: "", date: rec.firstReleaseDate ?? "",
                                          duration: Double(rec.length ?? 0) / 1000, recordingID: rec.id, releaseID: "", score: rec.score ?? 0)]
            }
            return releases.map { release in
                MetadataCandidate(id: rec.id + "/" + release.id, title: rec.title, artist: artist, album: release.title,
                                  date: release.date ?? rec.firstReleaseDate ?? "", duration: Double(rec.length ?? 0) / 1000,
                                  recordingID: rec.id, releaseID: release.id, score: rec.score ?? 0)
            }
        }
    }
    func cover(releaseID: String) async throws -> Data {
        guard UUID(uuidString: releaseID) != nil else { throw RivoError.message("Selecciona primero un lanzamiento de MusicBrainz.") }
        let u = URL(string: "https://coverartarchive.org/release/\(releaseID)/front-1200")!
        return try ArtworkCodec.prepare(await request(u, maxBytes: 20_000_000))
    }
    func artwork(url: URL) async throws -> Data {
        guard url.scheme == "https" else { throw RivoError.message("Usa un enlace HTTPS directo a una imagen.") }
        return try ArtworkCodec.prepare(await request(url, cache: false, maxBytes: 20_000_000))
    }
}
enum ServiceError: Error { case notFound }

enum ArtworkCodec {
    static func prepare(_ data: Data, maxPixels: Int = 1600) throws -> Data {
        guard !data.isEmpty, data.count <= 20_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.9) else {
            throw RivoError.message("No se pudo abrir la imagen o supera 20 MB.")
        }
        return jpeg
    }
}

struct MetadataCandidate: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let date: String
    let duration: Double
    let recordingID: String
    let releaseID: String
    let score: Int
    func tags(from existing: Tags, onlyEmpty: Bool = false) -> Tags {
        var t = existing
        for (k, v) in ["TITLE": title, "ARTIST": artist, "ALBUM": album, "DATE": date,
                        "MUSICBRAINZ_TRACKID": recordingID, "MUSICBRAINZ_ALBUMID": releaseID] {
            if !v.isEmpty, !onlyEmpty || t[k].isEmpty { t[k] = v }
        }
        return t
    }
    func isSafe(for track: Track) -> Bool {
        !track.tags["TITLE"].isEmpty && !track.artist.isEmpty && track.duration > 0 && duration > 0
        && Match.normalize(title) == Match.normalize(track.title) && Match.normalize(artist) == Match.normalize(track.artist)
        && abs(duration - track.duration) <= 2 && !track.album.isEmpty && Match.normalize(album) == Match.normalize(track.album)
    }
}
private struct MBSearch: Decodable { let recordings: [MBRecording]? }
private struct MBRecording: Decodable {
    let id: String; let title: String; let length: Int?; let score: Int?; let firstReleaseDate: String?
    let artistCredit: [MBCredit]?; let releases: [MBRelease]?
    enum CodingKeys: String, CodingKey { case id, title, length, score, releases; case artistCredit = "artist-credit"; case firstReleaseDate = "first-release-date" }
}
private struct MBCredit: Decodable { let name: String?; let joinphrase: String?; let artist: MBArtist? }
private struct MBArtist: Decodable { let name: String }
private struct MBRelease: Decodable { let id: String; let title: String; let date: String? }
