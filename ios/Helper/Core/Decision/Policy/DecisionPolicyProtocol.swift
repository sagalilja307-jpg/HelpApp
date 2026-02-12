//
//  DecisionPolicyProtocol.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-29.
//


import Foundation

/// Protokoll för en beslutsregel.
/// Returnerar ett beslutsförslag, eller `nil` om policyn inte matchar.
 protocol DecisionPolicyProtocol {
    func evaluate(suggestion: ActionSuggestion, context: DecisionContext) -> DecisionAction?
}
