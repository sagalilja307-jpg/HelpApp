import Foundation

enum UnifiedItemTypeDTO: String, Codable, Sendable {
    case email
    case event
    case task
    case reminder
    case note
    case contact
    case photo
    case file
    case location
}

struct UnifiedItemDTO: Codable, Sendable, Equatable {
    let id: String
    let source: String
    let type: UnifiedItemTypeDTO
    let title: String
    let body: String
    let createdAt: Date
    let updatedAt: Date
    let startAt: Date?
    let endAt: Date?
    let dueAt: Date?
    let status: [String: AnyCodable]

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case type
        case title
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startAt = "start_at"
        case endAt = "end_at"
        case dueAt = "due_at"
        case status
    }
}

struct IngestRequestDTO: Codable, Sendable {
    let items: [UnifiedItemDTO]
}

struct BackendQueryRequestDTO: Codable, Sendable {
    let query: String
    let question: String?
    let language: String
    let sources: [String]
    let days: Int
    let dataFilter: [String: AnyCodable]?

    init(
        query: String,
        question: String? = nil,
        language: String,
        sources: [String],
        days: Int,
        dataFilter: [String: AnyCodable]?
    ) {
        self.query = query
        self.question = question
        self.language = language
        self.sources = sources
        self.days = days
        self.dataFilter = dataFilter
    }

    enum CodingKeys: String, CodingKey {
        case query
        case question
        case language
        case sources
        case days
        case dataFilter = "data_filter"
    }
}

struct BackendDataIntentResponseDTO: Codable, Sendable {
    let dataIntent: BackendDataIntentDTO

    enum CodingKeys: String, CodingKey {
        case dataIntent = "data_intent"
    }
}

struct BackendDataIntentTimeframeDTO: Codable, Sendable, Equatable {
    let start: Date
    let end: Date
    let granularity: String
}

struct BackendDataIntentSortDTO: Codable, Sendable, Equatable {
    let field: String
    let direction: String
}

struct BackendDataIntentDTO: Codable, Sendable, Equatable {
    let domain: String
    let operation: String
    let timeframe: BackendDataIntentTimeframeDTO?
    let filters: [String: AnyCodable]?
    let sort: BackendDataIntentSortDTO?
    let limit: Int?
    let fields: [String]?
}
