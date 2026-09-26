import Foundation
import Security

struct ServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum OnlineSupport {
    static let agent = "RivoAudio-iOS/0.1.1 (https://github.com/Riv0Trill224/Rivo-Audio-iOS)"
    static func url(_ base: String, _ params: [String: String]) -> URL {
        var parts = URLComponents(string: base)!
        parts.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts.url!
    }
    static func json(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url); request.timeoutInterval = 25
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError(message: "La fuente no respondió correctamente. Intenta más tarde.")
        }
        return object
    }
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

enum SecureStore {
    private static let service = "com.riv0trill.rivoaudio.ios.lastfm"
    static func load() -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "credentials",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    static func save(_ data: Data) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "credentials"]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else {
                throw ServiceError(message: "No se pudieron guardar las credenciales en el llavero.")
            }
        } else if status != errSecSuccess { throw ServiceError(message: "No se pudo actualizar el llavero.") }
    }
}
