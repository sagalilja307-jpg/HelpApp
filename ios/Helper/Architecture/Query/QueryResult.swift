import Foundation

struct QueryResult: Codable, Equatable, Sendable {

    struct Entry: Codable, Equatable, Sendable, Identifiable {
        let id: UUID
        let source: QuerySource
        let title: String
        let body: String?
        let date: Date?
        let latitude: Double?
        let longitude: Double?

        init(
            id: UUID,
            source: QuerySource,
            title: String,
            body: String?,
            date: Date?,
            latitude: Double? = nil,
            longitude: Double? = nil
        ) {
            self.id = id
            self.source = source
            self.title = title
            self.body = body
            self.date = date
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    let timeRange: DateInterval?
    var entries: [Entry]
    var answer: String?
    var intentPlan: BackendIntentPlanDTO? = nil
}
