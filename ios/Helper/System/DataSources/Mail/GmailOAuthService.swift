import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

struct OAuthAuthorizationResult: Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
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
    case missingClientID
    case invalidAuthorizationURL
    case callbackMissingCode
    case callbackStateMismatch
    case callbackFailed
    case invalidTokenResponse
    case missingRefreshToken

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Gmail OAuth client id saknas i appkonfigurationen."
        case .invalidAuthorizationURL:
            return "Ogiltig authorization URL."
        case .callbackMissingCode:
            return "OAuth callback saknar authorization code."
        case .callbackStateMismatch:
            return "OAuth state matchade inte."
        case .callbackFailed:
            return "OAuth callback misslyckades."
        case .invalidTokenResponse:
            return "Ogiltigt token-svar från Google."
        case .missingRefreshToken:
            return "Saknar refresh token för att kunna uppdatera access token."
        }
    }
}

@MainActor
final class GmailOAuthService {
    private static let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    private let tokenManager: OAuthTokenManager

    init(tokenManager: OAuthTokenManager? = nil) {
        self.tokenManager = tokenManager ?? .shared
    }

    func startAuthorization() async throws -> OAuthAuthorizationResult {
        let op = "MailStartAuthorization"
        DataSourceDebug.start(op)
        do {
            let clientID = try resolveClientID()
            let codeVerifier = Self.makeCodeVerifier()
            let codeChallenge = Self.makeCodeChallenge(codeVerifier: codeVerifier)
            let state = Self.makeOAuthState()

            var components = URLComponents(url: Self.authURL, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: AppIntegrationConfig.gmailRedirectURI),
                URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/gmail.readonly"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: "S256")
            ]

            guard let authorizationURL = components?.url else {
                throw GmailOAuthServiceError.invalidAuthorizationURL
            }

            let callbackURL = try await Self.performAuthorizationSession(
                authorizationURL: authorizationURL,
                callbackScheme: AppIntegrationConfig.oauthCallbackScheme
            )

            let callback = Self.parseCallbackURL(callbackURL)
            guard callback.state == state else {
                throw GmailOAuthServiceError.callbackStateMismatch
            }

            guard let code = callback.code, !code.isEmpty else {
                throw GmailOAuthServiceError.callbackMissingCode
            }

            let token = try await exchangeToken(
                payload: [
                    "grant_type": "authorization_code",
                    "client_id": clientID,
                    "code": code,
                    "code_verifier": codeVerifier,
                    "redirect_uri": AppIntegrationConfig.gmailRedirectURI
                ]
            )

            let resolved = OAuthToken(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: DateService.shared.now().addingTimeInterval(TimeInterval(token.expiresIn))
            )
            await tokenManager.saveToken(resolved)

            DataSourceDebug.success(op)
            return OAuthAuthorizationResult(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: resolved.expiresAt
            )
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }

    func refreshAuthorization(refreshToken: String) async throws -> OAuthAuthorizationResult {
        let op = "MailRefreshAuthorization"
        DataSourceDebug.start(op)
        do {
            let clientID = try resolveClientID()
            let token = try await exchangeToken(
                payload: [
                    "grant_type": "refresh_token",
                    "client_id": clientID,
                    "refresh_token": refreshToken
                ]
            )

            let resolved = OAuthToken(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken ?? refreshToken,
                expiresAt: DateService.shared.now().addingTimeInterval(TimeInterval(token.expiresIn))
            )

            await tokenManager.saveToken(resolved)
            DataSourceDebug.success(op)
            return OAuthAuthorizationResult(
                accessToken: resolved.accessToken,
                refreshToken: resolved.refreshToken,
                expiresAt: resolved.expiresAt
            )
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }

    static func parseCallbackURL(_ url: URL) -> (code: String?, state: String?) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
        let state = components?.queryItems?.first(where: { $0.name == "state" })?.value
        return (code, state)
    }

    private func exchangeToken(payload: [String: String]) async throws -> GmailOAuthTokenResponse {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = payload.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let token = try JSONDecoder().decode(GmailOAuthTokenResponse.self, from: data)
        guard !token.accessToken.isEmpty else {
            throw GmailOAuthServiceError.invalidTokenResponse
        }
        return token
    }

    private func resolveClientID() throws -> String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "GMAIL_IOS_CLIENT_ID") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        if let value = ProcessInfo.processInfo.environment["HELPER_GMAIL_IOS_CLIENT_ID"],
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        if let value = UserDefaults.standard.string(forKey: "helper.gmail.ios_client_id"),
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        throw GmailOAuthServiceError.missingClientID
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

    private static func makeOAuthState() -> String {
        let bytes = (0..<24).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64URLEncodedString()
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
