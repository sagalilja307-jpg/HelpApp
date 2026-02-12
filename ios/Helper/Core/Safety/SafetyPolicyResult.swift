//
//  SafetyPolicyResult.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-29.
//


import Foundation

/// Result of evaluating user input for safety.
public enum SafetyPolicyResult {
    case allow
    case restrict(reason: SafetyRestriction)
}

/// Protocol for individual safety policies.
public protocol SafetyPolicyProtocol {
    func evaluate(input: String) -> SafetyPolicyResult
}
