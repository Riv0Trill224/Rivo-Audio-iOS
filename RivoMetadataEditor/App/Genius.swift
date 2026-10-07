import Foundation
import Security

// Personal client token stays in the device Keychain, never in project files.
enum GeniusCredentials {
    private static let service = "com.riv0trill.rivometadataeditor.genius"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "client-token",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String) throws {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "client-token"]
        if token.isEmpty {
            let status = SecItemDelete(key as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw RivoError.message("No se pudo borrar el token de Genius.") }
            return
        }
        let data = Data(token.utf8)
        let updated = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw RivoError.message("No se pudo actualizar el token de Genius.") }
        var insert = key
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw RivoError.message("No se pudo guardar el token de Genius.") }
    }
}

struct GeniusCandidate: Identifiable, Decodable, Sendable {
    let id: Int
    let title: String
    let url: URL
    let primaryArtist: Artist
    struct Artist: Decodable, Sendable { let name: String }
    enum CodingKeys: String, CodingKey { case id, title, url; case primaryArtist = "primary_artist" }
    var artist: String { primaryArtist.name }
    var pageURL: URL? {
        guard url.scheme == "https", url.host == "genius.com" || url.host?.hasSuffix(".genius.com") == true else { return nil }
        return url
    }
    func matches(title: String, artist: String) -> Bool {
        !title.isEmpty && !artist.isEmpty && Match.normalize(self.title) == Match.normalize(title)
            && Match.normalize(self.artist) == Match.normalize(artist)
    }
    static func searchURL(title: String, artist: String) -> URL {
        var c = URLComponents(string: "https://genius.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: [artist, title].filter { !$0.isEmpty }.joined(separator: " "))]
        return c.url!
    }
}
struct GeniusSearch: Decodable {
    let response: Response
    struct Response: Decodable { let hits: [Hit] }
    struct Hit: Decodable { let type: String?; let result: GeniusCandidate }
    var songs: [GeniusCandidate] {
        var seen: Set<Int> = []
        return response.hits.filter { $0.type == nil || $0.type == "song" }.map(\.result).filter { seen.insert($0.id).inserted && $0.pageURL != nil }
    }
}
