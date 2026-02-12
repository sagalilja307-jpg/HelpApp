//
//  DecisionLogger.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-27.
//


import Foundation
import SwiftData

/// Thin adapter between decision-making and persistent audit logging.
/// Owns NO business logic and NEVER affects user experience.
final class DecisionLogger {

    private let memoryService: MemoryService
    private let context: ModelContext

    init(
        memoryService: MemoryService,
        context: ModelContext
    ) {
        self.memoryService = memoryService
        self.context = context
    }

    /// Logs a system decision in an append-only, audit-safe way.
    func logDecision(
        action: DecisionAction,
        contentID: String,
        policy: DecisionPolicy,
        contextMode: TemporaryContextMode?
    ) {

        let reasons = buildReasons(
            action: action,
            policy: policy,
            contextMode: contextMode
        )

        do {
            try memoryService.appendDecision(
                actor: .system,
                decisionId: UUID().uuidString,
                action: action,
                reason: reasons,
                usedMemory: nil,
                in: context
            )
        } catch {
            // Intentionally ignored.
            // Decision logging must never interrupt the main flow.
        }
    }

    // MARK: - Reason construction (human-readable, deterministic)

    private func buildReasons(
        action: DecisionAction,
        policy: DecisionPolicy,
        contextMode: TemporaryContextMode?
    ) -> [String] {

        var reasons: [String] = []

        if let mode = contextMode {
            reasons.append("context:\(mode.rawValue)")
        }

        if policy.requireGentleResponses {
            reasons.append("gentle_responses")
        }

        if policy.allowLLM == false {
            reasons.append("llm_disabled_by_policy")
        }
        
        if action == .followUp {
            reasons.append("system_follow_up")
        }

        reasons.append("decision:\(action.rawValue)")

        return reasons
    }
}
