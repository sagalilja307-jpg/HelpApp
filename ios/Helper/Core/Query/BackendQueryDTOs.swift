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
    let features: IngestFeaturesDTO?

    init(
        items: [UnifiedItemDTO] = [],
        features: IngestFeaturesDTO? = nil
    ) {
        self.items = items
        self.features = features
    }
}

struct IngestFeaturesDTO: Codable, Sendable, Equatable {
    let calendarEvents: [CalendarFeatureEventIngestDTO]

    init(calendarEvents: [CalendarFeatureEventIngestDTO]) {
        self.calendarEvents = calendarEvents
    }

    enum CodingKeys: String, CodingKey {
        case calendarEvents = "calendar_events"
    }
}

struct CalendarFeatureEventIngestDTO: Codable, Sendable, Equatable {
    let id: String
    let eventIdentifier: String
    let title: String
    let notes: String?
    let location: String?
    let startAt: Date
    let endAt: Date
    let isAllDay: Bool
    let calendarTitle: String?
    let lastModifiedAt: Date?
    let snapshotHash: String

    enum CodingKeys: String, CodingKey {
        case id
        case eventIdentifier = "event_identifier"
        case title
        case notes
        case location
        case startAt = "start_at"
        case endAt = "end_at"
        case isAllDay = "is_all_day"
        case calendarTitle = "calendar_title"
        case lastModifiedAt = "last_modified_at"
        case snapshotHash = "snapshot_hash"
    }
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
    let analysis: BackendAnalysisDTO?
    let analysisReady: Bool?
    let requiresSources: [String]?
    let requirementReasonCodes: [String]?
    let requiredTimeWindow: BackendRequiredTimeWindowDTO?

    init(
        content: String,
        confidence: Double?,
        sourceDocuments: [String]?,
        evidenceItems: [EvidenceItemDTO]?,
        usedSources: [String]?,
        timeRange: BackendTimeRangeDTO?,
        analysis: BackendAnalysisDTO? = nil,
        analysisReady: Bool? = nil,
        requiresSources: [String]? = nil,
        requirementReasonCodes: [String]? = nil,
        requiredTimeWindow: BackendRequiredTimeWindowDTO? = nil
    ) {
        self.content = content
        self.confidence = confidence
        self.sourceDocuments = sourceDocuments
        self.evidenceItems = evidenceItems
        self.usedSources = usedSources
        self.timeRange = timeRange
        self.analysis = analysis
        self.analysisReady = analysisReady
        self.requiresSources = requiresSources
        self.requirementReasonCodes = requirementReasonCodes
        self.requiredTimeWindow = requiredTimeWindow
    }

    enum CodingKeys: String, CodingKey {
        case content
        case confidence
        case sourceDocuments = "source_documents"
        case evidenceItems = "evidence_items"
        case usedSources = "used_sources"
        case timeRange = "time_range"
        case analysis
        case analysisReady = "analysis_ready"
        case requiresSources = "requires_sources"
        case requirementReasonCodes = "requirement_reason_codes"
        case requiredTimeWindow = "required_time_window"
    }
}

struct BackendRequiredTimeWindowDTO: Codable, Sendable, Equatable {
    let start: Date
    let end: Date
    let granularity: String
}

struct BackendAnalysisTimeWindowDTO: Codable, Sendable {
    let start: Date
    let end: Date
    let granularity: String
}

struct BackendAnalysisDTO: Codable, Sendable {
    let intentId: String
    let timeWindow: BackendAnalysisTimeWindowDTO
    let insights: [AnyCodable]
    let patterns: [AnyCodable]
    let limitations: [String]
    let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case intentId = "intent_id"
        case timeWindow = "time_window"
        case insights
        case patterns
        case limitations
        case confidence
    }
}

struct BackendFeatureStatusDTO: Codable, Sendable, Equatable {
    let calendar: BackendCalendarFeatureStatusDTO?
}

struct BackendCalendarFeatureStatusDTO: Codable, Sendable, Equatable {
    let available: Bool
    let lastUpdated: Date?
    let coverageStart: Date?
    let coverageEnd: Date?
    let coverageDays: Int?
    let snapshotCount: Int
    let fresh: Bool
    let freshnessTTLHours: Int

    enum CodingKeys: String, CodingKey {
        case available
        case lastUpdated = "last_updated"
        case coverageStart = "coverage_start"
        case coverageEnd = "coverage_end"
        case coverageDays = "coverage_days"
        case snapshotCount = "snapshot_count"
        case fresh
        case freshnessTTLHours = "freshness_ttl_hours"
    }
}
