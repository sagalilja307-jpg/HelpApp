//
//  DecisionCoordinator.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-27.
//

import Foundation

@MainActor
final class DecisionCoordinator {

    private let pipeline = ActionSuggestionPipeline()
    private let decisionEngine = DecisionEngine()
    private let decisionLogger: DecisionLogger
    private let followUpEvaluator = FollowUpEvaluator()

    init(decisionLogger: DecisionLogger) {
        self.decisionLogger = decisionLogger
    }

    func handle(
        content: ContentObject,
        policy: DecisionPolicy,
        context: TemporaryContext?,
        clusterContext: ClusterContext? = nil,
        cluster: Cluster? = nil
    ) async -> ActionSuggestion? {

        // 🔁 E: Föreslå uppföljning om klustret väntar
        if var c = cluster, followUpEvaluator.evaluate(cluster: &c) {
            return ActionSuggestion(
                type: .followUp,
                title: "Följ upp?",
                explanation: "Du har inte fått svar än. Vill du skicka en påminnelse?",
                contentId: content.id,
                clusterId: c.clusterId
            )
        }

        // 🧠 Vanligt suggestionflöde
        let suggestion = await pipeline.suggestAction(
            for: content,
            policy: policy,
            clusterContext: clusterContext
        )

        guard let suggestion else {
            decisionLogger.logDecision(
                action: .noAction,
                contentID: content.id.uuidString,
                policy: policy,
                contextMode: context?.mode
            )
            return nil
        }

        let decision = decisionEngine.evaluate(
            suggestion: suggestion,
            policy: policy,
            context: context
        )

        decisionLogger.logDecision(
            action: decision,
            contentID: content.id.uuidString,
            policy: policy,
            contextMode: context?.mode
        )

        switch decision {
        case .suggested:
            return suggestion
        default:
            return nil
        }
    }
}

