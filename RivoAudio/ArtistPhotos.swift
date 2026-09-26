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
    private let jsonRequest: (URL) async throws -> [String: Any]
    private let imageRequest: (URL) async throws -> Data
    init(jsonRequest: @escaping (URL) async throws -> [String: Any] = OnlineSupport.json,
         imageRequest: @escaping (URL) async throws -> Data = OnlineSupport.imageData) {
        self.jsonRequest = jsonRequest; self.imageRequest = imageRequest
    }
    private func musicBrainz(_ url: URL) async throws -> [String: Any] {
        let delay = max(0, nextRequest.timeIntervalSinceNow)
        nextRequest = Date().addingTimeInterval(delay + 1.1)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        return try await jsonRequest(url)
    }
    func download(artist: String) async throws -> (Data, ArtistPhotoCredit) {
        if let lastFM = try? await lastFMPhoto(artist: artist) { return lastFM }
        return try await commonsPhoto(artist: artist)
    }
    private func lastFMPhoto(artist: String) async throws -> (Data, ArtistPhotoCredit) {
        guard let raw = SecureStore.load(),
              let stored = try JSONSerialization.jsonObject(with: raw) as? [String: String],
              let key = stored["key"], !key.isEmpty else {
            throw ServiceError(message: "Configura tu API key de Last.fm para buscar fotos.")
        }
        let response = try await jsonRequest(OnlineSupport.url("https://ws.audioscrobbler.com/2.0/",
            ["method": "artist.getinfo", "artist": artist, "api_key": key, "format": "json", "autocorrect": "1"]))
        guard let info = response["artist"] as? [String: Any],
              OnlineSupport.normalized(info["name"] as? String ?? "") == OnlineSupport.normalized(artist),
              let images = info["image"] as? [[String: Any]],
              let string = images.reversed().compactMap({ $0["#text"] as? String }).first(where: { !$0.isEmpty }),
              let photoURL = URL(string: string), photoURL.scheme == "https",
              let page = info["url"] as? String, let sourceURL = URL(string: page),
              sourceURL.scheme == "https", sourceURL.host == "www.last.fm" else {
            throw ServiceError(message: "Last.fm no tiene una foto de este artista.")
        }
        let data = try await imageRequest(photoURL)
        guard UIImage(data: data) != nil else { throw ServiceError(message: "La foto de Last.fm no es válida.") }
        return (data, ArtistPhotoCredit(musicBrainzID: "", sourceURL: sourceURL,
                                        author: "Last.fm", license: "Imagen de Last.fm", licenseURL: nil))
    }
    private func commonsPhoto(artist: String) async throws -> (Data, ArtistPhotoCredit) {
        // The artist is a quoted Lucene term; escape query syntax supplied in tags.
        let escaped = artist.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let search = try await musicBrainz(OnlineSupport.url("https://musicbrainz.org/ws/2/artist/", ["query": "artist:\"\(escaped)\"", "fmt": "json", "limit": "8"]))
        let normalized = OnlineSupport.normalized(artist)
        let candidates = (search["artists"] as? [[String: Any]] ?? []).filter {
            OnlineSupport.normalized($0["name"] as? String ?? "") == normalized
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
        let wikidata = try await jsonRequest(OnlineSupport.url("https://www.wikidata.org/w/api.php", ["action": "wbgetentities", "ids": entity, "props": "claims", "format": "json"]))
        let entities = wikidata["entities"] as? [String: Any]
        let record = entities?[entity] as? [String: Any]
        let claims = record?["claims"] as? [String: Any]
        let imageClaims = claims?["P18"] as? [[String: Any]] ?? []
        let claim = imageClaims.first { $0["rank"] as? String == "preferred" } ?? imageClaims.first { $0["rank"] as? String != "deprecated" }
        let snak = claim?["mainsnak"] as? [String: Any]
        let value = snak?["datavalue"] as? [String: Any]
        guard let filename = value?["value"] as? String else { throw ServiceError(message: "No hay foto disponible para este artista.") }
        let commons = try await jsonRequest(OnlineSupport.url("https://commons.wikimedia.org/w/api.php", ["action": "query", "titles": "File:\(filename)", "prop": "imageinfo", "iiprop": "url|extmetadata", "iiurlwidth": "600", "format": "json", "formatversion": "2"]))
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
        let data = try await imageRequest(imageURL)
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
            photoStatus[artist] = credit.license
            photoAttempts[artist] = Date(); savePhotoCredits()
        } catch {
            if Task.isCancelled { photoStatus[artist] = nil; return }
            photoAttempts[artist] = Date(); photoStatus[artist] = "Sin retrato: \(error.localizedDescription)"
        }
    }
    func savePhotoCredits() {
        if let data = try? JSONEncoder().encode(photoCredits) {
            try? data.write(to: documents.appendingPathComponent("artistPhotoCredits.json"), options: .atomic)
        }
    }
}
