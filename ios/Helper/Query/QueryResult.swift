import Foundation

struct QueryResult: Codable, Equatable, Sendable {

    struct Entry: Codable, Equatable, Sendable, Identifiable {
        let id: UUID
        let source: QuerySource
        let title: String
        let body: String?
        let date: Date?
        let endDate: Date?
        let isAllDay: Bool?
        let latitude: Double?
        let longitude: Double?

        enum CodingKeys: String, CodingKey {
            case id
            case source
            case title
            case body
            case date
            case endDate
            case isAllDay
            case latitude
            case longitude
        }

        nonisolated init(
            id: UUID,
            source: QuerySource,
            title: String,
            body: String?,
            date: Date?,
            endDate: Date? = nil,
            isAllDay: Bool? = nil,
            latitude: Double? = nil,
            longitude: Double? = nil
        ) {
            self.id = id
            self.source = source
            self.title = title
            self.body = body
            self.date = date
            self.endDate = endDate
            self.isAllDay = isAllDay
            self.latitude = latitude
            self.longitude = longitude
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(UUID.self, forKey: .id)
            self.source = try container.decode(QuerySource.self, forKey: .source)
            self.title = try container.decode(String.self, forKey: .title)
            self.body = try container.decodeIfPresent(String.self, forKey: .body)
            self.date = try container.decodeIfPresent(Date.self, forKey: .date)
            self.endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
            self.isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay)
            self.latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
            self.longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(source, forKey: .source)
            try container.encode(title, forKey: .title)
            try container.encodeIfPresent(body, forKey: .body)
            try container.encodeIfPresent(date, forKey: .date)
            try container.encodeIfPresent(endDate, forKey: .endDate)
            try container.encodeIfPresent(isAllDay, forKey: .isAllDay)
            try container.encodeIfPresent(latitude, forKey: .latitude)
            try container.encodeIfPresent(longitude, forKey: .longitude)
        }
    }

    let timeRange: DateInterval?
    var entries: [Entry]
    var answer: String?
    let intentPlan: BackendIntentPlanDTO?
}
