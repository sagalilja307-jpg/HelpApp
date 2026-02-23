//
//  SelfHarmRiskPolicy.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-29.
//


import Foundation

/// Detects risk of self-harm in user input.
public struct SelfHarmRiskPolicy: SafetyPolicyProtocol {

    private let riskKeywords = [
        "skada mig",
        "självskada",
        "ta mitt liv",
        "orkar inte leva",
        "vill inte finnas",
        "vill dö"
    ]

    public func evaluate(input: String) -> SafetyPolicyResult {
        let text = input.lowercased()
        for keyword in riskKeywords {
            if text.contains(keyword) {
                return .restrict(reason: .selfHarmRisk)
            }
        }
        return .allow
    }
}
