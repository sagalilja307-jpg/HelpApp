import Foundation
import SwiftData

enum LongTermMemoryType: String, CaseIterable, Sendable {
    case insight
    case idea
    case decision
    case question
    case risk
    case other

    static func map(from suggestedType: String) -> LongTermMemoryType {
        switch suggestedType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "insight":
            return .insight
        case "idea":
            return .idea
        case "decision":
            return .decision
        case "question":
            return .question
        case "risk":
            return .risk
        default:
            return .other
        }
    }
}

@Model
final class LongTermMemoryItem {
    @Attribute(.unique)
    var id: UUID

    var originalText: String
    var cleanText: String
    var suggestedType: String
    var tagsData: Data
    var embeddingData: Data
    var createdAt: Date
    var isUserEdited: Bool

    init(
        originalText: String,
        cleanText: String,
        suggestedType: String,
        tags: [String],
        embedding: [Float]
    ) {
        self.id = UUID()
        self.originalText = originalText
        self.cleanText = cleanText
        self.suggestedType = suggestedType
        self.tagsData = Self.encodeTags(tags)
        self.embeddingData = Self.encodeEmbedding(embedding)
        self.createdAt = DateService.shared.now()
        self.isUserEdited = false
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
        LongTermMemoryType.map(from: suggestedType)
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
