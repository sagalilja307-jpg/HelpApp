import SwiftData
import Foundation

@Model
public final class SemanticEmbedding {
    @Attribute(.unique) public var embeddingId: String
    public var sourceType: String
    public var sourceId: String
    public var vectorData: Data
    public var createdAt: Date

    public init(
        embeddingId: String,
        sourceType: String,
        sourceId: String,
        vectorData: Data,
        createdAt: Date = Date()
    ) {
        self.embeddingId = embeddingId
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.vectorData = vectorData
        self.createdAt = createdAt
    }

    /// Computed property: Decodes the stored Data into a [Double] vector
    public var vector: [Double] {
        vectorData.withUnsafeBytes {
            let floatArray = UnsafeBufferPointer<Float>(
                start: $0.bindMemory(to: Float.self).baseAddress!,
                count: vectorData.count / MemoryLayout<Float>.size
            )
            return floatArray.map { Double($0) }
        }
    }
}

