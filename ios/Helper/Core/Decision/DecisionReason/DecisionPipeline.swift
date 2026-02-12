//
//  DecisionPipeline.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-29.
//


import Foundation

/// En kedja av beslutsregler som evaluerar ett förslag.
public struct DecisionPipeline {
    private let policies: [DecisionPolicyProtocol]

     init(policies: [DecisionPolicyProtocol]) {
        self.policies = policies
    }

     func evaluate(suggestion: ActionSuggestion, context: DecisionContext) -> DecisionAction {
        for policy in policies {
            if let action = policy.evaluate(suggestion: suggestion, context: context) {
                return action
            }
        }
        return .noAction
    }
}
