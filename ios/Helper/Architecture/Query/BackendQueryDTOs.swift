import Foundation

enum UnifiedItemTypeDTO: String, Codable, Sendable {
    case email, event, task, reminder, note, contact, photo, file, location
}

// Behåll bara om ni fortfarande har ingest från iOS (annars kan ni flytta/ta bort)
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
        case id, source, type, title, body, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startAt = "start_at"
        case endAt = "end_at"
        case dueAt = "due_at"
    }
}

struct IngestRequestDTO: Codable, Sendable {
    let items: [UnifiedItemDTO]
}

// MARK: - Transport-only query

struct BackendQueryRequestDTO: Codable, Sendable {
    let query: String

    // valfria hints (ingen logik i klienten)
    let language: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case query, language, timezone
    }
}

struct BackendResolvedTimeframeDTO: Codable, Sendable, Equatable {
    let start: Date
    let end: Date
    let granularity: String?
}

struct BackendQueryEntryDTO: Codable, Sendable, Equatable {
    let id: String
    let source: String
    let type: UnifiedItemTypeDTO?
    let title: String
    let body: String?
    let date: Date?
}

struct BackendQueryResponseDTO: Codable, Sendable, Equatable {
    let answer: String
    let timeframe: BackendResolvedTimeframeDTO?
    let entries: [BackendQueryEntryDTO]

    // valfritt för UX/debug
    let missingAccess: [String]?

    enum CodingKeys: String, CodingKey {
        case answer, timeframe, entries
        case missingAccess = "missing_access"
    }
}
