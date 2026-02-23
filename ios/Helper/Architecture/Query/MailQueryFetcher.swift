import Foundation
import SwiftData

typealias DataIntent = BackendIntentPlanDTO

protocol MailFetching {
    func fetch(for intent: DataIntent) async throws -> [ContentObject]
}

@MainActor
struct MailQueryFetcher: MailFetching {
    private let tokenManager: OAuthTokenManager
    private let oauthService: GmailOAuthService
    private let mailSyncService: MailSyncService
    private let memoryService: MemoryService
    private let maxResults: Int

    init(
        memoryService: MemoryService,
        tokenManager: OAuthTokenManager? = nil,
        oauthService: GmailOAuthService? = nil,
        mailSyncService: MailSyncService? = nil,
        maxResults: Int = 50
    ) {
        self.memoryService = memoryService
        self.tokenManager = tokenManager ?? .shared
        self.oauthService = oauthService ?? GmailOAuthService(tokenManager: self.tokenManager)
        self.mailSyncService = mailSyncService ?? .shared
        self.maxResults = max(1, min(maxResults, 100))
    }

    func fetch(for intent: DataIntent) async throws -> [ContentObject] {
        let token = try await ensureValidToken()
        let gmailQuery = Self.makeGmailQuery(
            intent: intent,
            timeRange: nil,
            userQuery: nil
        )
        let messages = try await mailSyncService.fetchMessages(
            accessToken: token.accessToken,
            gmailQuery: gmailQuery,
            maxResults: maxResults
        )
        return mailSyncService.makeContentObjects(from: messages)
    }

    func collect(
        for intent: DataIntent,
        timeRange: DateInterval?,
        userQuery: UserQuery
    ) async throws -> LocalCollectedResult {
        let token = try await ensureValidToken()
        let gmailQuery = Self.makeGmailQuery(
            intent: intent,
            timeRange: timeRange,
            userQuery: userQuery.text
        )
        let context = memoryService.context()
        let entries = try await mailSyncService.syncInbox(
            accessToken: token.accessToken,
            gmailQuery: gmailQuery,
            maxResults: maxResults,
            memory: memoryService,
            in: context
        )
        return LocalCollectedResult(entries: entries)
    }
}

private extension MailQueryFetcher {
    func ensureValidToken() async throws -> OAuthToken {
        if let token = try? await tokenManager.loadToken() {
            return token
        }

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

    static func makeGmailQuery(
        intent: DataIntent,
        timeRange: DateInterval?,
        userQuery: String?
    ) -> String? {
        var terms: [String] = []

        if let status = intent.filters["status"]?.value as? String,
           status.lowercased() == "unread" {
            terms.append("is:unread")
        }

        if let timeRange {
            terms.append(contentsOf: gmailDateTerms(from: timeRange))
        } else {
            terms.append(contentsOf: gmailDateTerms(from: intent.timeScope))
        }

        if let userQuery {
            let lowered = userQuery.lowercased()
            if lowered.contains("oläst") || lowered.contains("olästa") || lowered.contains("unread") {
                if !terms.contains("is:unread") {
                    terms.append("is:unread")
                }
            }
        }

        guard !terms.isEmpty else { return nil }
        return terms.joined(separator: " ")
    }

    static func gmailDateTerms(from interval: DateInterval) -> [String] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        return [
            "after:\(gmailDateString(start))",
            "before:\(gmailDateString(nextDay))"
        ]
    }

    static func gmailDateTerms(from timeScope: BackendTimeScopeDTO) -> [String] {
        switch timeScope.type {
        case .all:
            return []
        case .absolute:
            guard
                let value = timeScope.value,
                let date = parseDate(value)
            else { return [] }
            let dayStart = Calendar.current.startOfDay(for: date)
            let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            return [
                "after:\(gmailDateString(dayStart))",
                "before:\(gmailDateString(nextDay))"
            ]
        case .relative:
            guard let value = timeScope.value else { return [] }
            switch value {
            case "7d", "30d", "3m", "1y":
                return ["newer_than:\(value)"]
            case "today", "today_morning", "today_day", "today_afternoon", "today_evening":
                let today = Calendar.current.startOfDay(for: DateService.shared.now())
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
                return [
                    "after:\(gmailDateString(today))",
                    "before:\(gmailDateString(tomorrow))"
                ]
            case "yesterday":
                let today = Calendar.current.startOfDay(for: DateService.shared.now())
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
                return [
                    "after:\(gmailDateString(yesterday))",
                    "before:\(gmailDateString(today))"
                ]
            default:
                if value.hasSuffix("d") || value.hasSuffix("m") || value.hasSuffix("y") {
                    return ["newer_than:\(value)"]
                }
                return []
            }
        }
    }

    static func gmailDateString(_ date: Date) -> String {
        DateService.shared.dateFormatter(dateFormat: "yyyy/MM/dd").string(from: date)
    }

    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if let parsed = ISO8601DateFormatter().date(from: trimmed) {
            return parsed
        }

        let formatter = DateService.shared.dateFormatter(dateFormat: "yyyy-MM-dd")
        return formatter.date(from: String(trimmed.prefix(10)))
    }
}
