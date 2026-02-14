import Foundation

enum MailSyncError: Error {
    case failedToFetch
}

final class MailSyncService {
    static let shared = MailSyncService()

    private init() {}

    func fetchUnansweredMails() async throws -> [Mail] {
        let data = try await HelperAPIClient.shared.get(
            path: "/mail/unanswered",
            queryItems: [URLQueryItem(name: "since", value: "2024-01-01"),
                         URLQueryItem(name: "limit", value: "50")]
        )
        return try JSONDecoder().decode([Mail].self, from: data)
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
