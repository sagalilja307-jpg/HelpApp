//
//  FollowUpClusterHandler.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-29.
//


import Foundation

/// Handles marking clusters as waiting after certain decisions
final class FollowUpClusterHandler: DecisionActionHandler {
    func handle(decision: DecisionAction, target: Any) {
        guard let cluster = target as? Cluster else {
            assertionFailure("FollowUpClusterHandler expected Cluster target")
            return
        }

        FollowUpManager.shared.markClusterWaitingForResponse(cluster)
    }
}
