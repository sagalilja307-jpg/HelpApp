import Foundation

enum LongTermMemoryVectorMath {
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for index in a.indices {
            let left = a[index]
            let right = b[index]
            dot += left * right
            normA += left * left
            normB += right * right
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }

    static func normalized(_ vector: [Float]) -> [Float] {
        guard !vector.isEmpty else { return [] }
        let magnitude = sqrt(vector.reduce(0) { $0 + ($1 * $1) })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    static func mean(of vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first, !first.isEmpty else { return [] }

        var sum = Array(repeating: Float(0), count: first.count)
        for vector in vectors where vector.count == first.count {
            for index in vector.indices {
                sum[index] += vector[index]
            }
        }

        let count = Float(vectors.count)
        guard count > 0 else { return [] }
        return sum.map { $0 / count }
    }
}
