//
//  ClusterMatcher.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-28.
//


import Foundation

final class ClusterMatcher {

    private let rules = ClusterMatchingRules()

    func match(
        embedding: SemanticEmbedding,
        eventDate: Date,
        existingClusters: [Cluster]
    ) -> (cluster: Cluster?, similarity: Double) {

        var bestCluster: Cluster?
        var bestScore: Double = 0

        for cluster in existingClusters {

            // 1️⃣ Cosine similarity mellan event embedding och kluster centroid
            let similarity = cosineSimilarity(
                embedding.vector,
                cluster.centroid
            )

            // 2️⃣ Hur många dagar sedan klustret uppdaterades
            let daysDiff = abs(Calendar.current.dateComponents(
                [.day],
                from: cluster.updatedAt,   // ✅ FIX
                to: eventDate
            ).day ?? Int.max)

            // 3️⃣ Boost similarity baserat på tidsavstånd
            let boosted = rules.boostedSimilarity(
                baseSimilarity: similarity,
                timeDifferenceInDays: daysDiff
            )

            if boosted > bestScore {
                bestScore = boosted
                bestCluster = cluster
            }
        }

        return (bestCluster, bestScore)
    }

    // MARK: - Cosine Similarity

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        let dot = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }
}
