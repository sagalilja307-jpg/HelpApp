//
//  ClusterEngine.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-28.
//


import Foundation

final class ClusterEngine {
    private let matcher = ClusterMatcher()
    private let evaluator = ClusterLifecycleEvaluator()
    private let store: ClusterStore

    init(store: ClusterStore) {
        self.store = store
    }

    func ingest(rawEvent: RawEvent) -> Cluster {
        // 🚀 1. Vektorisera texten
        let vector = vectorize(rawEvent.text ?? "")
        
        // 🚀 2. Skapa en temporär embedding
        let embedding = SemanticEmbedding(
            embeddingId: UUID().uuidString,
            sourceType: "raw_event",
            sourceId: rawEvent.id,
            vectorData: vector.toData()
        )

        // 🧠 3. Matcha mot befintliga kluster
        let (matchedCluster, similarity) = matcher.match(
            embedding: embedding,
            eventDate: rawEvent.createdAt,
            existingClusters: store.allClusters()
        )

        // 🎯 4. Beslutslogik (förläng eller skapa nytt)
        let decision = evaluator.decide(
            cluster: matchedCluster,
            similarity: similarity
        )

        switch decision {
        case .extend(let cluster):
            let item = ClusterItem(
                cluster: cluster,
                event: rawEvent,
                addedAt: rawEvent.createdAt
            )
            cluster.addItem(item)
            store.updateCluster(cluster)
            return cluster

        case .uncertain, .createNew:
            let clusterId = UUID().uuidString
            let newCluster = Cluster(
                clusterId: clusterId,
                label: "", // Fyll i om du har en label
                proposedBy: .system,
                updatedAt: rawEvent.createdAt,
                centroid: embedding.vector.map { Double($0) }
            )
            let item = ClusterItem(
                cluster: newCluster,
                event: rawEvent,
                addedAt: rawEvent.createdAt
            )
            newCluster.addItem(item)
            store.addCluster(newCluster)
            return newCluster
        }
    }
}
