import Foundation

struct QueryResult: Codable, Equatable, Sendable {

    struct Entry: Codable, Equatable, Sendable, Identifiable {
        let id: UUID
        let source: QuerySource
        let title: String
        let body: String?
        let date: Date?
    }

    let timeRange: DateInterval?
    var entries: [Entry]           // måste vara var
    var answer: String?            // ✅ ny property
    var backendAnalyticsIntent: String?
}
