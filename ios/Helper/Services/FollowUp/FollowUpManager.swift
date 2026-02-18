import Foundation
import SwiftData

final class FollowUpManager {

    static let shared = FollowUpManager()
    private init() {}

    private let evaluator = FollowUpEvaluator()

    // MARK: - Evaluate clusters and generate follow-up suggestions

    /// Called on app launch, background refresh, or periodic trigger
    func evaluateClustersForFollowUps(clusters: [Cluster]) -> [Cluster] {
        var updatedClusters: [Cluster] = []

        for cluster in clusters {
            var mutable = cluster

            if evaluator.evaluate(cluster: &mutable) {
                print("🔔 Follow-up suggested for cluster \(mutable.clusterId)")
            }

            updatedClusters.append(mutable)
        }

        return updatedClusters
    }

    // MARK: - When user sends a message (enter waiting state)

    func markClusterWaitingForResponse(_ cluster: Cluster) {
        guard cluster.status != .archived else {
            print("⚠️ Can't mark archived cluster as waiting.")
            return
        }

        cluster.status = .waitingForResponse
        cluster.waitingSince = DateService.shared.now()
        cluster.followUpSuggested = false
    }

    // MARK: - When new activity arrives (exit waiting state)

    func markClusterActive(_ cluster: Cluster) {
        guard cluster.status == .waitingForResponse else {
            print("ℹ️ Cluster is not in waiting state.")
            return
        }

        cluster.status = .active
        cluster.waitingSince = nil
        cluster.followUpSuggested = false
    }
}
