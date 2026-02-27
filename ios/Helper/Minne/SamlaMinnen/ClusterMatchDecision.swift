//
//  ClusterMatchDecision.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-28.
//


import Foundation

enum ClusterMatchDecision {
    case extend(Cluster)
    case createNew
    case uncertain(Cluster)
}

final class ClusterLifecycleEvaluator {

    private let rules = ClusterMatchingRules()

    func decide(
        cluster: Cluster?,
        similarity: Double
    ) -> ClusterMatchDecision {

        guard let cluster else {
            return .createNew
        }

        if similarity >= rules.strongMatchThreshold {
            return .extend(cluster)
        }

        if similarity >= rules.weakMatchThreshold {
            return .uncertain(cluster)
        }

        return .createNew
    }
}
