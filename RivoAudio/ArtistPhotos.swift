import Foundation
import UIKit

struct ArtistPhotoCredit: Codable {
    let musicBrainzID: String
    let sourceURL: URL
    let author: String
    let license: String
    let licenseURL: URL?
}

actor ArtistPhotoSource {
    static let shared = ArtistPhotoSource()
    private var nextRequest = Date.distantPast
    private func musicBrainz(_ url: URL) async throws -> [String: Any] {
        let delay = max(0, nextRequest.timeIntervalSinceNow)
        nextRequest = Date().addingTimeInterval(delay + 1.1)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return try await OnlineSupport.json(url)
    }
    func download(artist: String) async throws -> (Data, ArtistPhotoCredit) {
        // The artist is a quoted Lucene term; escape query syntax supplied in tags.
        let escaped = artist.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let search = try await musicBrainz(OnlineSupport.url("https://musicbrainz.org/ws/2/artist/", ["query": "artist:\"\(escaped)\"", "fmt": "json", "limit": "8"]))
        let candidates = (search["artists"] as? [[String: Any]] ?? []).filter {
            OnlineSupport.normalized($0["name"] as? String ?? "") == OnlineSupport.normalized(artist)
        }
        guard candidates.count == 1, let id = candidates.first?["id"] as? String else {
            throw ServiceError(message: "No hay una identidad única para este artista. Revisa su nombre en los metadatos.")
        }
        let detail = try await musicBrainz(OnlineSupport.url("https://musicbrainz.org/ws/2/artist/\(id)", ["inc": "url-rels", "fmt": "json"]))
        let relations = detail["relations"] as? [[String: Any]] ?? []
        let resource = relations.first { $0["type"] as? String == "wikidata" }?["url"] as? [String: Any]
        guard let link = resource?["resource"] as? String, let entity = URL(string: link)?.lastPathComponent,
              entity.range(of: #"^Q[0-9]+$"#, options: .regularExpression) != nil else {
            throw ServiceError(message: "El artista no tiene una fotografía vinculada en esta fuente.")
        }
        let wikidata = try await OnlineSupport.json(OnlineSupport.url("https://www.wikidata.org/w/api.php", ["action": "wbgetentities", "ids": entity, "props": "claims", "format": "json"]))
        let entities = wikidata["entities"] as? [String: Any]
        let record = entities?[entity] as? [String: Any]
        let claims = record?["claims"] as? [String: Any]
        let imageClaims = claims?["P18"] as? [[String: Any]] ?? []
        let claim = imageClaims.first { $0["rank"] as? String == "preferred" } ?? imageClaims.first { $0["rank"] as? String != "deprecated" }
        let snak = claim?["mainsnak"] as? [String: Any]
        let value = snak?["datavalue"] as? [String: Any]
        guard let filename = value?["value"] as? String else { throw ServiceError(message: "No hay foto disponible para este artista.") }
        let commons = try await OnlineSupport.json(OnlineSupport.url("https://commons.wikimedia.org/w/api.php", ["action": "query", "titles": "File:\(filename)", "prop": "imageinfo", "iiprop": "url|extmetadata", "iiurlwidth": "600", "format": "json", "formatversion": "2"]))
        let query = commons["query"] as? [String: Any]
        let pages = query?["pages"] as? [[String: Any]]
        let info = (pages?.first?["imageinfo"] as? [[String: Any]])?.first
        let meta = info?["extmetadata"] as? [String: Any] ?? [:]
        func field(_ name: String) -> String { (meta[name] as? [String: Any])?["value"] as? String ?? "" }
        guard let thumb = info?["thumburl"] as? String, let imageURL = URL(string: thumb),
              imageURL.scheme == "https", imageURL.host == "upload.wikimedia.org",
              let source = info?["descriptionurl"] as? String, let sourceURL = URL(string: source),
              sourceURL.host == "commons.wikimedia.org", !field("LicenseShortName").isEmpty else {
            throw ServiceError(message: "No se encontró una foto con fuente y licencia identificables.")
        }
        var request = URLRequest(url: imageURL); request.timeoutInterval = 25
        request.setValue(OnlineSupport.agent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 10_000_000 else {
            throw ServiceError(message: "No se pudo descargar la fotografía.")
        }
        let author = field("Artist").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
        return (data, ArtistPhotoCredit(musicBrainzID: id, sourceURL: sourceURL, author: author, license: field("LicenseShortName"), licenseURL: URL(string: field("LicenseUrl"))))
    }
}

extension MusicLibrary {
    func loadArtistPhoto(_ artist: String, refresh: Bool = false) async {
        guard !photoRequests.contains(artist), refresh || photoCredits[artist] == nil else { return }
        if !refresh, let tried = photoAttempts[artist], Date().timeIntervalSince(tried) < 86400 { return }
        photoRequests.insert(artist); photoStatus[artist] = "Buscando fotografía…"
        defer { photoRequests.remove(artist) }
        do {
            let (data, credit) = try await ArtistPhotoSource.shared.download(artist: artist)
            guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) else { throw ServiceError(message: "La imagen no tiene un formato válido.") }
            try setArtistPhoto(jpeg, for: artist)
            photoCredits[artist] = credit
            photoStatus[artist] = "Wikimedia Commons · \(credit.license)"
            photoAttempts[artist] = Date(); savePhotoCredits()
        } catch {
            photoAttempts[artist] = Date(); photoStatus[artist] = error.localizedDescription
        }
    }
    func savePhotoCredits() {
        if let data = try? JSONEncoder().encode(photoCredits) {
            try? data.write(to: documents.appendingPathComponent("artistPhotoCredits.json"), options: .atomic)
        }
    }
}
