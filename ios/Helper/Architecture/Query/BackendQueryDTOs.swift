import Foundation

enum UnifiedItemTypeDTO: String, Codable, Sendable {
    case email, event, task, reminder, note, contact, photo, file, location
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

struct BackendQueryRequestDTO: Codable, Sendable {
    let query: String
    let language: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case query, language, timezone
    }
}

enum BackendIntentDomain: String, Codable, Sendable, Equatable {
    case calendar
    case reminders
    case mail
    case notes
    case files
    case photos
    case contacts
    case location
    case memory
}

enum BackendIntentMode: String, Codable, Sendable, Equatable {
    case info
}

enum BackendIntentOperation: String, Codable, Sendable, Equatable {
    case count
    case list
    case sum
    case sumDuration = "sum_duration"
    case groupByDay = "group_by_day"
    case groupByType = "group_by_type"
    case latest
    case exists
    case needsClarification = "needs_clarification"
}

enum BackendTimeScopeType: String, Codable, Sendable, Equatable {
    case relative
    case absolute
    case all
}

enum BackendTimeScopeValue: String, Codable, Sendable, Equatable {
    case today
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case threeMonths = "3m"
    case oneYear = "1y"
}

enum BackendIntentGrouping: String, Codable, Sendable, Equatable {
    case day
    case week
    case month
    case type
    case location
    case status
    case none
}

enum BackendIntentSortOption: String, Codable, Sendable, Equatable {
    case dateDesc = "date_desc"
    case dateAsc = "date_asc"
    case duration
    case name
    case priority
    case none
}

struct BackendTimeScopeDTO: Codable, Sendable, Equatable {
    let type: BackendTimeScopeType
    let value: String?
    let start: Date?
    let end: Date?
}

struct BackendIntentPlanDTO: Codable, Sendable, Equatable {
    let domain: BackendIntentDomain?
    let mode: BackendIntentMode
    let operation: BackendIntentOperation
    let timeScope: BackendTimeScopeDTO
    let filters: [String: AnyCodable]
    let grouping: BackendIntentGrouping?
    let sort: BackendIntentSortOption?
    let needsClarification: Bool
    let clarificationMessage: String?
    let suggestions: [BackendIntentDomain]

    enum CodingKeys: String, CodingKey {
        case domain
        case mode
        case operation
        case timeScope = "time_scope"
        case filters
        case grouping
        case sort
        case needsClarification = "needs_clarification"
        case clarificationMessage = "clarification_message"
        case suggestions
    }

    init(
        domain: BackendIntentDomain?,
        mode: BackendIntentMode,
        operation: BackendIntentOperation,
        timeScope: BackendTimeScopeDTO,
        filters: [String: AnyCodable],
        grouping: BackendIntentGrouping?,
        sort: BackendIntentSortOption?,
        needsClarification: Bool,
        clarificationMessage: String?,
        suggestions: [BackendIntentDomain]
    ) {
        self.domain = domain
        self.mode = mode
        self.operation = operation
        self.timeScope = timeScope
        self.filters = filters
        self.grouping = grouping
        self.sort = sort
        self.needsClarification = needsClarification
        self.clarificationMessage = clarificationMessage
        self.suggestions = suggestions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawDomain = try container.decodeIfPresent(String.self, forKey: .domain)
        let needsClarification = try container.decodeIfPresent(Bool.self, forKey: .needsClarification) ?? false

        if let rawDomain, rawDomain.lowercased() == "system" {
            self.domain = nil
        } else if let rawDomain {
            self.domain = BackendIntentDomain(rawValue: rawDomain)
        } else {
            self.domain = nil
        }

        self.mode = try container.decodeIfPresent(BackendIntentMode.self, forKey: .mode) ?? .info

        if let rawOperation = try container.decodeIfPresent(String.self, forKey: .operation),
           let mappedOperation = BackendIntentOperation(rawValue: rawOperation) {
            self.operation = mappedOperation
        } else {
            self.operation = needsClarification ? .needsClarification : .count
        }

        self.timeScope = try container.decode(BackendTimeScopeDTO.self, forKey: .timeScope)
        self.filters = try container.decodeIfPresent([String: AnyCodable].self, forKey: .filters) ?? [:]
        self.grouping = try container.decodeIfPresent(BackendIntentGrouping.self, forKey: .grouping)
        self.sort = try container.decodeIfPresent(BackendIntentSortOption.self, forKey: .sort)
        self.needsClarification = needsClarification
        self.clarificationMessage = try container.decodeIfPresent(String.self, forKey: .clarificationMessage)
        let rawSuggestions = try container.decodeIfPresent([String].self, forKey: .suggestions) ?? []
        self.suggestions = rawSuggestions.compactMap(BackendIntentDomain.init(rawValue:))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(domain?.rawValue, forKey: .domain)
        try container.encode(mode, forKey: .mode)
        try container.encode(operation, forKey: .operation)
        try container.encode(timeScope, forKey: .timeScope)
        try container.encode(filters, forKey: .filters)
        try container.encodeIfPresent(grouping, forKey: .grouping)
        try container.encodeIfPresent(sort, forKey: .sort)
        try container.encode(needsClarification, forKey: .needsClarification)
        try container.encodeIfPresent(clarificationMessage, forKey: .clarificationMessage)
        try container.encode(suggestions.map(\.rawValue), forKey: .suggestions)
    }
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
    let intentPlan: BackendIntentPlanDTO
    let answer: String?
    let entries: [BackendQueryEntryDTO]?
    let missingAccess: [String]?
    let hasDataIntent: Bool

    enum CodingKeys: String, CodingKey {
        case intentPlan = "intent_plan"
        case dataIntent = "data_intent"
        case answer
        case entries
        case missingAccess = "missing_access"
    }

    init(
        intentPlan: BackendIntentPlanDTO,
        answer: String? = nil,
        entries: [BackendQueryEntryDTO]? = nil,
        missingAccess: [String]? = nil,
        hasDataIntent: Bool = false
    ) {
        self.intentPlan = intentPlan
        self.answer = answer
        self.entries = entries
        self.missingAccess = missingAccess
        self.hasDataIntent = hasDataIntent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let plan = try container.decodeIfPresent(BackendIntentPlanDTO.self, forKey: .intentPlan) {
            self.intentPlan = plan
            self.hasDataIntent = false
        } else if let dataIntent = try container.decodeIfPresent(BackendIntentPlanDTO.self, forKey: .dataIntent) {
            self.intentPlan = dataIntent
            self.hasDataIntent = true
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
}
