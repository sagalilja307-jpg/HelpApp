//
//  SupportiveModePolicy.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-29.
//


import Foundation

/// Förhindrar att systemet föreslår något alls i "supportive" mode.
public struct SupportiveModePolicy: DecisionPolicyProtocol {
     func evaluate(suggestion: ActionSuggestion, context: DecisionContext) -> DecisionAction? {
        if context.temporaryContext?.mode == .supportive {
            return .noAction
        }
        return nil
    }
}
