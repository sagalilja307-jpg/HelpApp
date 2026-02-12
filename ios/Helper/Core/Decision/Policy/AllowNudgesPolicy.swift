//
//  AllowNudgesPolicy.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-29.
//


import Foundation

/// Blockerar alla förslag om nudges inte är tillåtna enligt policy.
public struct AllowNudgesPolicy: DecisionPolicyProtocol {
    func evaluate(suggestion: ActionSuggestion, context: DecisionContext) -> DecisionAction? {
        if context.policy.allowNudges == false {
            return .noAction
        }
        return nil
    }
}
