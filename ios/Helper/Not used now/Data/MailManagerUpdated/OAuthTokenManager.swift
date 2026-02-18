import Foundation

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

    private let storageKey = "oauth_token"
    private let userDefaults = UserDefaults.standard

    private init() {}

    func saveToken(_ token: OAuthToken) async {
        do {
            let data = try JSONEncoder().encode(token)
            userDefaults.set(data, forKey: storageKey)
            HelperAPIClient.shared.setAccessToken(token.accessToken)
        } catch {
            print("Kunde inte spara token: \(error)")
        }
    }

    func loadToken() async throws -> OAuthToken {
        guard let data = userDefaults.data(forKey: storageKey) else {
            throw URLError(.userAuthenticationRequired)
        }

        let token = try JSONDecoder().decode(OAuthToken.self, from: data)

        if token.isExpired {
            throw URLError(.userAuthenticationRequired)
        }

        HelperAPIClient.shared.setAccessToken(token.accessToken)
        return token
    }

    func clearToken() {
        userDefaults.removeObject(forKey: storageKey)
    }
}
