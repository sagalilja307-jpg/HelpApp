//
//  SuggestionTypePolicy.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-29.
//


import Foundation

/// Tar beslut baserat på typ av förslag.
 struct SuggestionTypePolicy: DecisionPolicyProtocol {
     func evaluate(suggestion: ActionSuggestion, context: DecisionContext) -> DecisionAction? {
        switch suggestion.type {
        case .calendar, .reminder, .sendMessage:
            return context.policy.allowNudges ? .suggested : .noAction

        case .note:
            return .suggested

        case .followUp:
            if let cluster = context.clusterContext, cluster.followUpSuggested == true {
                return .noAction
            }
            return context.policy.allowNudges ? .suggested : .noAction

        case .ignore:
            return .noAction
        }
    }
}
