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
}
