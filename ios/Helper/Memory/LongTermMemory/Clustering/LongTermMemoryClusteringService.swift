import Foundation
import SwiftData

struct LongTermMemoryClusteringService {
    private struct Sample {
        let item: LongTermMemoryItem
        let vector: [Float]
    }

    private let maxIterations: Int = 20
    private let maxClusterCount: Int = 8

    func loadClusters(
        in context: ModelContext,
        preferredClusterCount: Int? = nil
    ) throws -> [LongTermMemoryCluster] {
        let descriptor = FetchDescriptor<LongTermMemoryItem>(
            sortBy: [SortDescriptor(\LongTermMemoryItem.createdAt, order: .forward)]
        )
        let items = try context.fetch(descriptor)
        return cluster(items: items, preferredClusterCount: preferredClusterCount)
    }

    func cluster(
        items: [LongTermMemoryItem],
        preferredClusterCount: Int? = nil
    ) -> [LongTermMemoryCluster] {
        let samples = validSamples(from: items)
        guard !samples.isEmpty else { return [] }

        let k = clusterCount(for: samples.count, preferred: preferredClusterCount)
        guard k > 0 else { return [] }

        var centroids = initialCentroids(from: samples.map(\.vector), count: k)
        var assignments = Array(repeating: 0, count: samples.count)

        for _ in 0..<maxIterations {
            var changed = false

            for index in samples.indices {
                let best = nearestCentroidIndex(for: samples[index].vector, centroids: centroids)
                if assignments[index] != best {
                    assignments[index] = best
                    changed = true
                }
            }

            var grouped = Array(repeating: [[Float]](), count: centroids.count)
            for index in assignments.indices {
                grouped[assignments[index]].append(samples[index].vector)
            }

            for centroidIndex in centroids.indices {
                let members = grouped[centroidIndex]
                if members.isEmpty {
                    centroids[centroidIndex] = fallbackCentroid(
                        for: centroidIndex,
                        samples: samples,
                        existingCentroids: centroids
                    )
                } else {
                    centroids[centroidIndex] = LongTermMemoryVectorMath.normalized(
                        LongTermMemoryVectorMath.mean(of: members)
                    )
                }
            }

            if !changed {
                break
            }
        }

        var membership: [Int: [Sample]] = [:]
        for index in assignments.indices {
            membership[assignments[index], default: []].append(samples[index])
        }

        let clusters = membership
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .compactMap { entry -> LongTermMemoryCluster? in
                let members = entry.value
                guard !members.isEmpty else { return nil }

                let memberIDs = members.map { $0.item.id }
                let topTags = topTags(for: members)
                let dominantType = dominantType(for: members)
                let sampleText = members.first?.item.cleanText

                return LongTermMemoryCluster(
                    id: entry.key,
                    memberIDs: memberIDs,
                    centroid: centroids[entry.key],
                    topTags: topTags,
                    dominantType: dominantType,
                    sampleText: sampleText
                )
            }

        return clusters.sorted {
            if $0.itemCount == $1.itemCount {
                return $0.id < $1.id
            }
            return $0.itemCount > $1.itemCount
        }
    }

    private func validSamples(from items: [LongTermMemoryItem]) -> [Sample] {
        let ordered = items.sorted { $0.createdAt < $1.createdAt }

        guard let dimension = ordered.first(where: { !$0.embedding.isEmpty })?.embedding.count else {
            return []
        }

        return ordered.compactMap { item in
            let vector = item.embedding
            guard vector.count == dimension, !vector.isEmpty else { return nil }
            return Sample(item: item, vector: LongTermMemoryVectorMath.normalized(vector))
        }
    }

    private func clusterCount(for sampleCount: Int, preferred: Int?) -> Int {
        guard sampleCount > 0 else { return 0 }

        if let preferred {
            return max(1, min(preferred, sampleCount))
        }

        let heuristic = Int(Double(sampleCount).squareRoot().rounded())
        let bounded = max(1, min(heuristic, maxClusterCount))
        return min(bounded, sampleCount)
    }

    private func initialCentroids(from vectors: [[Float]], count: Int) -> [[Float]] {
        guard count > 0 else { return [] }
        guard vectors.count > 1 else { return [vectors[0]] }

        if count == 1 {
            return [vectors[0]]
        }

        let lastIndex = vectors.count - 1
        return (0..<count).map { index in
            let ratio = Double(index) / Double(max(1, count - 1))
            let vectorIndex = Int((ratio * Double(lastIndex)).rounded())
            return vectors[vectorIndex]
        }
    }

    private func nearestCentroidIndex(for vector: [Float], centroids: [[Float]]) -> Int {
        var bestIndex = 0
        var bestScore = -Float.greatestFiniteMagnitude

        for index in centroids.indices {
            let score = LongTermMemoryVectorMath.cosineSimilarity(vector, centroids[index])
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        return bestIndex
    }

    private func fallbackCentroid(
        for clusterIndex: Int,
        samples: [Sample],
        existingCentroids: [[Float]]
    ) -> [Float] {
        let sampleIndex = (clusterIndex * 997) % samples.count
        let candidate = samples[sampleIndex].vector

        // Keep deterministic behavior while nudging away from centroid duplicates.
        for centroid in existingCentroids {
            if LongTermMemoryVectorMath.cosineSimilarity(candidate, centroid) >= 0.9999 {
                continue
            }
            return candidate
        }

        return candidate
    }

    private func topTags(for members: [Sample]) -> [String] {
        var counts: [String: Int] = [:]
        for member in members {
            for tag in member.item.tags {
                let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty else { continue }
                counts[normalized, default: 0] += 1
            }
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(5)
            .map(\.key)
    }

    private func dominantType(for members: [Sample]) -> LongTermMemoryType {
        var counts: [LongTermMemoryType: Int] = [:]
        for member in members {
            counts[member.item.normalizedType, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.rawValue < rhs.key.rawValue
                }
                return lhs.value > rhs.value
            }
            .first?
            .key ?? .other
    }
}
