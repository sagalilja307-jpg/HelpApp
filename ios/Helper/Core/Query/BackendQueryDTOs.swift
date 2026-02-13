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
    let language: String
    let sources: [String]
    let days: Int
    let dataFilter: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case query
        case language
        case sources
        case days
        case dataFilter = "data_filter"
    }
}

struct BackendTimeRangeDTO: Codable, Sendable {
    let start: Date
    let end: Date
    let days: Int
}

struct EvidenceItemDTO: Codable, Sendable {
    let id: String
    let source: String
    let type: String?
    let title: String
    let body: String
    let date: Date?
    let url: String?
}

struct BackendLLMResponseDTO: Codable, Sendable {
    let content: String
    let confidence: Double?
    let sourceDocuments: [String]?
    let evidenceItems: [EvidenceItemDTO]?
    let usedSources: [String]?
    let timeRange: BackendTimeRangeDTO?

    enum CodingKeys: String, CodingKey {
        case content
        case confidence
        case sourceDocuments = "source_documents"
        case evidenceItems = "evidence_items"
        case usedSources = "used_sources"
        case timeRange = "time_range"
    }
}
