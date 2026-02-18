import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

struct OAuthAuthorizationResult: Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
}

private struct GmailOAuthStartResponse: Codable {
    let authorizationURL: String
    let state: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case authorizationURL = "authorization_url"
        case state
        case expiresIn = "expires_in"
    }
}

private struct GmailOAuthExchangeRequest: Codable {
    let code: String
    let codeVerifier: String
    let state: String
    let redirectURI: String

    enum CodingKeys: String, CodingKey {
        case code
        case codeVerifier = "code_verifier"
        case state
        case redirectURI = "redirect_uri"
    }
}

private struct GmailOAuthRefreshRequest: Codable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct GmailOAuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum GmailOAuthServiceError: LocalizedError {
    case invalidAuthorizationURL
    case callbackMissingCode
    case callbackStateMismatch
    case callbackFailed
    case missingRefreshToken

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizationURL:
            return "Ogiltig authorization URL från backend."
        case .callbackMissingCode:
            return "OAuth callback saknar authorization code."
        case .callbackStateMismatch:
            return "OAuth state matchade inte."
        case .callbackFailed:
            return "OAuth callback misslyckades."
        case .missingRefreshToken:
            return "Saknar refresh token för att kunna uppdatera access token."
        }
    }
}

@MainActor
final class GmailOAuthService {
    private let helperAPIClient: HelperAPIClient
    private let tokenManager: OAuthTokenManager

    init(
        helperAPIClient: HelperAPIClient? = nil,
        tokenManager: OAuthTokenManager? = nil
    ) {
        self.helperAPIClient = helperAPIClient ?? .shared
        self.tokenManager = tokenManager ?? .shared
    }

    func startAuthorization() async throws -> OAuthAuthorizationResult {
        let codeVerifier = Self.makeCodeVerifier()
        let codeChallenge = Self.makeCodeChallenge(codeVerifier: codeVerifier)

        let startData = try await helperAPIClient.get(
            path: "/oauth/gmail/start",
            queryItems: [
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "redirect_uri", value: AppIntegrationConfig.gmailRedirectURI)
            ]
        )

        let decoder = JSONDecoder()
        let start = try decoder.decode(GmailOAuthStartResponse.self, from: startData)

        guard let authorizationURL = URL(string: start.authorizationURL) else {
            throw GmailOAuthServiceError.invalidAuthorizationURL
        }

        let callbackURL = try await Self.performAuthorizationSession(
            authorizationURL: authorizationURL,
            callbackScheme: AppIntegrationConfig.oauthCallbackScheme
        )

        let callback = Self.parseCallbackURL(callbackURL)
        guard callback.state == start.state else {
            throw GmailOAuthServiceError.callbackStateMismatch
        }

        guard let code = callback.code, !code.isEmpty else {
            throw GmailOAuthServiceError.callbackMissingCode
        }

        let exchangeBody = try JSONEncoder().encode(
            GmailOAuthExchangeRequest(
                code: code,
                codeVerifier: codeVerifier,
                state: start.state,
                redirectURI: AppIntegrationConfig.gmailRedirectURI
            )
        )

        let tokenData = try await helperAPIClient.post(path: "/oauth/gmail/exchange", body: exchangeBody)
        let token = try decoder.decode(GmailOAuthTokenResponse.self, from: tokenData)

        let resolved = OAuthToken(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: DateService.shared.now().addingTimeInterval(TimeInterval(token.expiresIn))
        )
        await tokenManager.saveToken(resolved)

        return OAuthAuthorizationResult(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: resolved.expiresAt
        )
    }

    func refreshAuthorization(refreshToken: String) async throws -> OAuthAuthorizationResult {
        let body = try JSONEncoder().encode(GmailOAuthRefreshRequest(refreshToken: refreshToken))
        let data = try await helperAPIClient.post(path: "/oauth/gmail/refresh", body: body)
        let token = try JSONDecoder().decode(GmailOAuthTokenResponse.self, from: data)

        let resolved = OAuthToken(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? refreshToken,
            expiresAt: DateService.shared.now().addingTimeInterval(TimeInterval(token.expiresIn))
        )

        await tokenManager.saveToken(resolved)
        return OAuthAuthorizationResult(
            accessToken: resolved.accessToken,
            refreshToken: resolved.refreshToken,
            expiresAt: resolved.expiresAt
        )
    }

    static func parseCallbackURL(_ url: URL) -> (code: String?, state: String?) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
        let state = components?.queryItems?.first(where: { $0.name == "state" })?.value
        return (code, state)
    }

    private static func performAuthorizationSession(
        authorizationURL: URL,
        callbackScheme: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                OAuthSessionHolder.activeSession = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(throwing: GmailOAuthServiceError.callbackFailed)
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = WebAuthenticationContextProvider.shared
            OAuthSessionHolder.activeSession = session
            session.start()
        }
    }

    static func makeCodeVerifier() -> String {
        let bytes = (0..<48).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64URLEncodedString()
    }

    static func makeCodeChallenge(codeVerifier: String) -> String {
        let data = Data(codeVerifier.utf8)
        let digest = CryptoKit.SHA256.hash(data: data)
        return Data(digest).base64URLEncodedString()
    }
}

private final class WebAuthenticationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthenticationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
        if let keyWindow {
            return keyWindow
        }
        if let scene = scenes.first {
            return ASPresentationAnchor(windowScene: scene)
        }
        fatalError("No UIWindowScene available for OAuth presentation.")
    }
}

private enum OAuthSessionHolder {
    static var activeSession: ASWebAuthenticationSession?
}

private extension Data {
    func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
