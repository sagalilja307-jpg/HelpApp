import Foundation

enum MailSyncError: Error {
    case failedToFetch
}

final class MailSyncService {
    static let shared = MailSyncService()

    private init() {}

    func fetchUnansweredMails(since: String? = nil, limit: Int = 50) async throws -> [Mail] {
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let since {
            queryItems.append(URLQueryItem(name: "since", value: since))
        }
        let data = try await HelperAPIClient.shared.get(
            path: "/mail/unanswered",
            queryItems: queryItems
        )
        return try BackendQueryAPIService.decoder.decode([Mail].self, from: data)
    }

    func fetchRecentMails(days: Int = 30, limit: Int = 50) async throws -> [Mail] {
        let data = try await HelperAPIClient.shared.get(
            path: "/mail/recent",
            queryItems: [
                URLQueryItem(name: "days", value: String(days)),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        return try BackendQueryAPIService.decoder.decode([Mail].self, from: data)
    }

    func fetchMails(fromDomain domain: String, limit: Int = 50) async throws -> [Mail] {
        let data = try await HelperAPIClient.shared.get(
            path: "/mail/from-domain",
            queryItems: [
                URLQueryItem(name: "domain", value: domain),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        return try BackendQueryAPIService.decoder.decode([Mail].self, from: data)
    }

    func syncGmail(
        accessToken: String,
        days: Int = 90,
        maxResults: Int = 50
    ) async throws {
        HelperAPIClient.shared.setAccessToken(accessToken)

        let payload: [String: Any] = [
            "access_token": accessToken,
            "days": days,
            "max_results": maxResults
        ]

        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        _ = try await HelperAPIClient.shared.post(path: "/sync/gmail", body: body)
    }
}
