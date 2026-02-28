import Foundation
import SwiftData

enum LongTermMemoryType: String, CaseIterable, Sendable {
    case decision
    case idea
    case reflection
    case question
    case risk
    case insight
    case other

    static func map(from cognitiveType: String) -> LongTermMemoryType {
        switch cognitiveType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "decision":
            return .decision
        case "idea":
            return .idea
        case "reflection":
            return .reflection
        case "question":
            return .question
        case "risk":
            return .risk
        case "insight":
            return .insight
        default:
            return .other
        }
    }
}

extension LongTermMemoryType {
    var displayName: String {
        switch self {
        case .decision:
            return "Decision"
        case .idea:
            return "Idea"
        case .reflection:
            return "Reflection"
        case .question:
            return "Question"
        case .risk:
            return "Risk"
        case .insight:
            return "Insight"
        case .other:
            return "Other"
        }
    }
}

enum LongTermMemoryDomain: String, CaseIterable, Sendable {
    case work
    case relationship
    case health
    case finance
    case logistics
    case place
    case learning
    case project
    case selfDomain = "self"
    case other

    static func map(from domain: String) -> LongTermMemoryDomain {
        switch domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "work":
            return .work
        case "relationship":
            return .relationship
        case "health":
            return .health
        case "finance":
            return .finance
        case "logistics":
            return .logistics
        case "place":
            return .place
        case "learning":
            return .learning
        case "project":
            return .project
        case "self":
            return .selfDomain
        default:
            return .other
        }
    }

    var displayName: String {
        switch self {
        case .work:
            return "Work"
        case .relationship:
            return "Relationship"
        case .health:
            return "Health"
        case .finance:
            return "Finance"
        case .logistics:
            return "Logistics"
        case .place:
            return "Place"
        case .learning:
            return "Learning"
        case .project:
            return "Project"
        case .selfDomain:
            return "Self"
        case .other:
            return "Other"
        }
    }
}

enum LongTermMemoryActionState: String, CaseIterable, Sendable {
    case info
    case todo
    case done
    case plan
    case decide
    case question
    case observe

    static func map(from actionState: String) -> LongTermMemoryActionState {
        switch actionState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "todo":
            return .todo
        case "done":
            return .done
        case "plan":
            return .plan
        case "decide":
            return .decide
        case "question":
            return .question
        case "observe":
            return .observe
        default:
            return .info
        }
    }

    var displayName: String {
        switch self {
        case .info:
            return "Info"
        case .todo:
            return "Todo"
        case .done:
            return "Done"
        case .plan:
            return "Plan"
        case .decide:
            return "Decide"
        case .question:
            return "Question"
        case .observe:
            return "Observe"
        }
    }
}

enum LongTermMemoryTimeRelation: String, CaseIterable, Sendable {
    case past
    case present
    case future
    case recurring
    case timeless
    case explicitDate
    case relativeTime
    case none

    static func map(from timeRelation: String) -> LongTermMemoryTimeRelation {
        switch timeRelation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "past":
            return .past
        case "present":
            return .present
        case "future":
            return .future
        case "recurring":
            return .recurring
        case "timeless":
            return .timeless
        case "explicitdate":
            return .explicitDate
        case "relativetime":
            return .relativeTime
        default:
            return .none
        }
    }

    var displayName: String {
        switch self {
        case .past:
            return "Past"
        case .present:
            return "Present"
        case .future:
            return "Future"
        case .recurring:
            return "Recurring"
        case .timeless:
            return "Timeless"
        case .explicitDate:
            return "Explicit Date"
        case .relativeTime:
            return "Relative Time"
        case .none:
            return "None"
        }
    }
}

@Model
final class LongTermMemoryItem {
    @Attribute(.unique)
    var id: UUID

    var originalText: String
    var cleanText: String
    @Attribute(originalName: "suggestedType")
    var cognitiveType: String = "other"
    var domain: String = "other"
    var actionState: String = "info"
    var timeRelation: String = "none"
    var tagsData: Data
    var embeddingData: Data
    var createdAt: Date
    var updatedAt: Date = Date.distantPast
    var isUserEdited: Bool

    init(
        originalText: String,
        cleanText: String,
        cognitiveType: String,
        domain: String,
        actionState: String,
        timeRelation: String,
        tags: [String],
        embedding: [Float]
    ) {
        let now = DateService.shared.now()
        self.id = UUID()
        self.originalText = originalText
        self.cleanText = cleanText
        self.cognitiveType = cognitiveType
        self.domain = domain
        self.actionState = actionState
        self.timeRelation = timeRelation
        self.tagsData = Self.encodeTags(tags)
        self.embeddingData = Self.encodeEmbedding(embedding)
        self.createdAt = now
        self.updatedAt = now
        self.isUserEdited = false
    }

    convenience init(
        originalText: String,
        cleanText: String,
        suggestedType: String,
        tags: [String],
        embedding: [Float]
    ) {
        self.init(
            originalText: originalText,
            cleanText: cleanText,
            cognitiveType: suggestedType,
            domain: "other",
            actionState: "info",
            timeRelation: "none",
            tags: tags,
            embedding: embedding
        )
    }

    var tags: [String] {
        get { Self.decodeTags(tagsData) }
        set { tagsData = Self.encodeTags(newValue) }
    }

    var embedding: [Float] {
        get { Self.decodeEmbedding(embeddingData) }
        set { embeddingData = Self.encodeEmbedding(newValue) }
    }

    var normalizedType: LongTermMemoryType {
        LongTermMemoryType.map(from: cognitiveType)
    }

    var normalizedDomain: LongTermMemoryDomain {
        LongTermMemoryDomain.map(from: domain)
    }

    var normalizedActionState: LongTermMemoryActionState {
        LongTermMemoryActionState.map(from: actionState)
    }

    var normalizedTimeRelation: LongTermMemoryTimeRelation {
        LongTermMemoryTimeRelation.map(from: timeRelation)
    }

    // Transitional alias while callers migrate from suggestedType naming.
    var suggestedType: String {
        get { cognitiveType }
        set { cognitiveType = newValue }
    }

    private static func encodeTags(_ value: [String]) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data("[]".utf8)
    }

    private static func decodeTags(_ data: Data) -> [String] {
        (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func encodeEmbedding(_ value: [Float]) -> Data {
        value.withUnsafeBufferPointer {
            Data(buffer: UnsafeBufferPointer(start: $0.baseAddress, count: $0.count))
        }
    }

    private static func decodeEmbedding(_ data: Data) -> [Float] {
        data.withUnsafeBytes { rawBuffer in
            let bound = rawBuffer.bindMemory(to: Float.self)
            guard let base = bound.baseAddress else { return [] }
            return Array(UnsafeBufferPointer(start: base, count: bound.count))
        }
    }
}
