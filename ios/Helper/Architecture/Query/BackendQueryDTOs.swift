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

// MARK: - Intent plan (nya svaret)

struct BackendTimeIntentDTO: Codable, Sendable, Equatable {
    let category: String
    let payload: AnyCodable?
}

struct BackendResolvedTimeframeDTO: Codable, Sendable, Equatable {
    let start: Date
    let end: Date
    let granularity: String?
}

struct BackendIntentPlanDTO: Codable, Sendable, Equatable {
    let domain: String?
    let operation: String
    let timeIntent: BackendTimeIntentDTO
    let timeframe: BackendResolvedTimeframeDTO?
    let needsClarification: Bool
    let suggestions: [String]

    enum CodingKeys: String, CodingKey {
        case domain
        case operation
        case timeIntent = "time_intent"
        case timeframe
        case needsClarification = "needs_clarification"
        case suggestions
    }
}

// MARK: - Entries (om/när backend returnerar data)

struct BackendQueryEntryDTO: Codable, Sendable, Equatable {
    let id: String
    let source: String
    let type: UnifiedItemTypeDTO?
    let title: String
    let body: String?
    let date: Date?
}

private struct BackendDataIntentDTO: Codable, Sendable, Equatable {
    let domain: String?
    let operation: String
    let timeframe: BackendResolvedTimeframeDTO?
    let filters: [String: AnyCodable]?
}

// MARK: - Response (stöder både "plan-only" och framtida "answer/entries")

struct BackendQueryResponseDTO: Codable, Sendable, Equatable {
    let intentPlan: BackendIntentPlanDTO

    // valfria fält (om du senare låter backend även returnera svar + items)
    let answer: String?
    let entries: [BackendQueryEntryDTO]?
    let missingAccess: [String]?

    enum CodingKeys: String, CodingKey {
        case intentPlan = "intent_plan"
        case dataIntent = "data_intent"
        case answer
        case entries
        case missingAccess = "missing_access"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let plan = try container.decodeIfPresent(BackendIntentPlanDTO.self, forKey: .intentPlan) {
            self.intentPlan = plan
        } else if let dataIntent = try container.decodeIfPresent(BackendDataIntentDTO.self, forKey: .dataIntent) {
            let needsClarification =
                dataIntent.operation == "needs_clarification" ||
                dataIntent.domain?.lowercased() == "system"

            let suggestions = Self.extractSuggestions(from: dataIntent.filters)

            self.intentPlan = BackendIntentPlanDTO(
                domain: needsClarification ? nil : dataIntent.domain,
                operation: dataIntent.operation,
                timeIntent: BackendTimeIntentDTO(category: "NONE", payload: nil),
                timeframe: dataIntent.timeframe,
                needsClarification: needsClarification,
                suggestions: suggestions
            )
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.intentPlan,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Missing both intent_plan and data_intent in query response."
                )
            )
        }

        self.answer = try container.decodeIfPresent(String.self, forKey: .answer)
        self.entries = try container.decodeIfPresent([BackendQueryEntryDTO].self, forKey: .entries)
        self.missingAccess = try container.decodeIfPresent([String].self, forKey: .missingAccess)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(intentPlan, forKey: .intentPlan)
        try container.encodeIfPresent(answer, forKey: .answer)
        try container.encodeIfPresent(entries, forKey: .entries)
        try container.encodeIfPresent(missingAccess, forKey: .missingAccess)
    }

    private static func extractSuggestions(from filters: [String: AnyCodable]?) -> [String] {
        guard let raw = filters?["suggested_domains"]?.value as? [Any] else { return [] }
        return raw.compactMap { $0 as? String }
    }
}
