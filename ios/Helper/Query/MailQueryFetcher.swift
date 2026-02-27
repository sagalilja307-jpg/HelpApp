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

        if let statusTerm = statusSearchTerm(from: intent.filters) {
            terms.append(statusTerm)
        }

        if let timeRange {
            terms.append(contentsOf: gmailDateTerms(from: timeRange))
        } else {
            terms.append(contentsOf: gmailDateTerms(from: intent.timeScope))
        }

        if let attachmentTerm = attachmentSearchTerm(from: intent.filters) {
            terms.append(attachmentTerm)
        }

        if let priorityTerm = prioritySearchTerm(from: intent.filters) {
            terms.append(priorityTerm)
        }

        let senders = senderTerms(from: intent.filters)
        for sender in senders {
            terms.append("from:\(gmailQuoted(sender))")
        }

        let textContainsTerms = textSearchTerms(from: intent.filters)
        for term in textContainsTerms {
            terms.append(gmailQuoted(term))
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

    static func senderTerms(from filters: [String: AnyCodable]) -> [String] {
        let hints = ["from", "sender", "participants", "participant", "domain", "company", "brand", "org", "organization"]
        var collected: [String] = []

        for (key, value) in filters {
            collectSenderTerms(
                value: value.value,
                key: key.lowercased(),
                keyHints: hints,
                output: &collected
            )
        }

        var seen: Set<String> = []
        return collected.filter { term in
            let normalized = term.lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
    }

    static func collectSenderTerms(
        value: Any,
        key: String,
        keyHints: [String],
        output: inout [String]
    ) {
        switch value {
        case let text as String:
            guard keyHints.contains(where: { key.contains($0) }) else { return }
            output.append(contentsOf: splitTerms(text))

        case let nested as [String: Any]:
            for (nestedKey, nestedValue) in nested {
                collectSenderTerms(
                    value: nestedValue,
                    key: nestedKey.lowercased(),
                    keyHints: keyHints,
                    output: &output
                )
            }

        case let array as [Any]:
            for item in array {
                collectSenderTerms(
                    value: item,
                    key: key,
                    keyHints: keyHints,
                    output: &output
                )
            }

        case let nestedAnyCodables as [String: AnyCodable]:
            for (nestedKey, nestedValue) in nestedAnyCodables {
                collectSenderTerms(
                    value: nestedValue.value,
                    key: nestedKey.lowercased(),
                    keyHints: keyHints,
                    output: &output
                )
            }

        case let anyCodableArray as [AnyCodable]:
            for item in anyCodableArray {
                collectSenderTerms(
                    value: item.value,
                    key: key,
                    keyHints: keyHints,
                    output: &output
                )
            }

        default:
            return
        }
    }

    static func splitTerms(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func statusSearchTerm(from filters: [String: AnyCodable]) -> String? {
        guard let status = filters["status"]?.value as? String else { return nil }
        switch status.lowercased() {
        case "unread":
            return "is:unread"
        default:
            return nil
        }
    }

    static func attachmentSearchTerm(from filters: [String: AnyCodable]) -> String? {
        guard let hasAttachment = filters["has_attachment"]?.value as? Bool else { return nil }
        return hasAttachment ? "has:attachment" : "-has:attachment"
    }

    static func prioritySearchTerm(from filters: [String: AnyCodable]) -> String? {
        guard let priority = filters["priority"]?.value as? String else { return nil }
        switch priority.lowercased() {
        case "high":
            return "is:important"
        default:
            return nil
        }
    }

    static func textSearchTerms(from filters: [String: AnyCodable]) -> [String] {
        guard let raw = filters["text_contains"]?.value else { return [] }

        switch raw {
        case let text as String:
            return splitTerms(text)
        case let values as [String]:
            return values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        case let values as [Any]:
            return values.compactMap { value in
                guard let text = value as? String else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        default:
            return []
        }
    }

    static func entityTerms(fromQuery query: String) -> [String] {
        let stopwords: Set<String> = [
            "vad", "har", "jag", "for", "fran", "från", "med", "mina", "mitt",
            "vilken", "vilket", "dag", "datum", "gör", "gor", "nasta", "nästa",
            "vecka", "manad", "månad", "ar", "år", "idag", "imorgon", "igar",
            "igår", "today", "tomorrow", "yesterday", "week", "month", "year",
            "mail", "mejl", "email", "from"
        ]

        let tokens = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { token in
                guard token.count >= 2 else { return false }
                return !stopwords.contains(token)
            }

        if tokens.count <= 3 {
            return tokens
        }
        return []
    }

    static func gmailQuoted(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.contains(" ") {
            let escaped = trimmed.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return trimmed
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
