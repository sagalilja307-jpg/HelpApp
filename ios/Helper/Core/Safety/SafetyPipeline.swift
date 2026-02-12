//
//  SafetyPipeline.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-29.
//


import Foundation

/// Runs all safety policies in order and returns the first restriction found.
public struct SafetyPipeline {
    private let policies: [SafetyPolicyProtocol]

    public init(policies: [SafetyPolicyProtocol]) {
        self.policies = policies
    }

    public func evaluate(input: String) -> SafetyPolicyResult {
        for policy in policies {
            let result = policy.evaluate(input: input)
            if case .restrict = result {
                return result
            }
        }
        return .allow
    }
}
