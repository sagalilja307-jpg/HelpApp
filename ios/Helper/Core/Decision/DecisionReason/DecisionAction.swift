//
//  DecisionAction.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-25.
//


import Foundation

/// Represents the system's decision outcome or internal system events.
/// This does NOT represent user intent or UI actions.
public enum DecisionAction: String, Codable, Sendable {

    // MARK: - Decision outcomes (from DecisionEngine)

    case noAction    = "no_action"
    case suggested   = "suggested"
    case suppressed  = "suppressed"

    // MARK: - System follow-up actions (executed after user consent)

    case scheduled   = "scheduled"
    case followUp    = "follow_up"
    case messageSent = "message_sent" // 👈 NY

    // MARK: - Safety-related system boundaries

    case safetyBoundaryTriggered = "safety_boundary_triggered"
    case safetyAcknowledged      = "safety_acknowledged"

    // MARK: - Context / state transitions

    case contextChanged          = "context_changed"
}
