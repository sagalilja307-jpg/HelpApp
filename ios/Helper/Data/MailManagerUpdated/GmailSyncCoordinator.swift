import Foundation

@MainActor
final class GmailSyncCoordinator {
    private let tokenManager: OAuthTokenManager
    private let oauthService: GmailOAuthService
    private let mailSyncService: MailSyncService

    init(
        tokenManager: OAuthTokenManager? = nil,
        oauthService: GmailOAuthService? = nil,
        mailSyncService: MailSyncService? = nil
    ) {
        self.tokenManager = tokenManager ?? .shared
        self.oauthService = oauthService ?? GmailOAuthService()
        self.mailSyncService = mailSyncService ?? .shared
    }

    func syncInbox(days: Int = 90, maxResults: Int = 50) async throws {
        let token = try await ensureValidToken()
        try await mailSyncService.syncGmail(
            accessToken: token.accessToken,
            days: days,
            maxResults: maxResults
        )
    }

    private func ensureValidToken() async throws -> OAuthToken {
        let token = try tokenManager.loadStoredToken()
        guard token.isExpired else { return token }

        guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
            throw GmailOAuthServiceError.missingRefreshToken
        }

        let refreshed = try await oauthService.refreshAuthorization(refreshToken: refreshToken)
        return OAuthToken(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresAt: refreshed.expiresAt
        )
    }
}
