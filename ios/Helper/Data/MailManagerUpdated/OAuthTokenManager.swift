import Foundation
import Security

struct OAuthToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date

    var isExpired: Bool {
        return DateService.shared.now() >= expiresAt
    }
}

final class OAuthTokenManager {
    static let shared = OAuthTokenManager()

    private let service = "saga.com.Helper.gmail.oauth"
    private let account = "default"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func saveToken(_ token: OAuthToken) async {
        do {
            let data = try encoder.encode(token)
            try saveToKeychain(data)
        } catch {
            print("Kunde inte spara token: \(error)")
        }
    }

    func loadToken() async throws -> OAuthToken {
        let token = try loadStoredToken()

        if token.isExpired {
            throw URLError(.userAuthenticationRequired)
        }

        return token
    }

    func loadStoredToken() throws -> OAuthToken {
        guard let data = try readFromKeychain() else {
            throw URLError(.userAuthenticationRequired)
        }
        return try decoder.decode(OAuthToken.self, from: data)
    }

    func hasStoredToken() -> Bool {
        do {
            return try readFromKeychain() != nil
        } catch {
            return false
        }
    }

    func hasValidToken() -> Bool {
        guard let token = try? loadStoredToken() else { return false }
        return !token.isExpired
    }

    func clearToken() {
        _ = try? deleteFromKeychain()
    }
}

private extension OAuthTokenManager {
    var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func saveToKeychain(_ data: Data) throws {
        try deleteFromKeychain()
        var query = baseQuery
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func readFromKeychain() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return item as? Data
    }

    func deleteFromKeychain() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
