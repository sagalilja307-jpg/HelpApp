//
//  DecisionHandler.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-28.
//


import Foundation

/// Defines how the system responds to a given decision and target (e.g. a cluster).
protocol DecisionActionHandler {
    func handle(decision: DecisionAction, target: Any)
}

/// Main entry point for handling decisions.
final class DecisionHandler {

    static let shared = DecisionHandler()

    private var handlers: [DecisionAction: DecisionActionHandler] = [:]

    private init() {
        registerDefaultHandlers()
    }

    /// Applies a decision to a target (e.g. a Cluster)
    func apply(decision: DecisionAction, to target: Any) {
        guard let handler = handlers[decision] else {
            // No handler registered → do nothing
            return
        }
        handler.handle(decision: decision, target: target)
    }

    /// Register a custom handler (if needed in tests or modules)
    func registerHandler(_ action: DecisionAction, handler: DecisionActionHandler) {
        handlers[action] = handler
    }

    /// Built-in default mappings
    private func registerDefaultHandlers() {
        handlers[.messageSent] = FollowUpClusterHandler()
        handlers[.scheduled] = FollowUpClusterHandler()
        // Lägg till fler här vid behov
    }
}
