//
//  ClusterStore.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-28.
//


import SwiftData

final class ClusterStore {

    let modelContext: ModelContext

    init(context: ModelContext) {
        self.modelContext = context
    }

    func addCluster(_ cluster: Cluster) {
        modelContext.insert(cluster)
        try? modelContext.save()
    }

    func updateCluster(_ cluster: Cluster) {
        try? modelContext.save()
    }

    func allClusters() -> [Cluster] {
        let descriptor = FetchDescriptor<Cluster>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
