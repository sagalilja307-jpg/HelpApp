//
//  ChatViewModel.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-30.
//

import Foundation
import Observation

@MainActor
@Observable
final class ChatViewModel {

    struct ChatMessage: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        let text: String
        let visualizationComponent: VisualizationComponent?
        let filters: [String: AnyCodable]
        let entries: [QueryResult.Entry]
        let timeRange: DateInterval?
        let intentPlan: BackendIntentPlanDTO?
        let timestamp: Date = .now
    }

    // MARK: - UI-state

    var messages: [ChatMessage] = []
    var query: String = ""
    var extraContext: String = ""
    var isSending = false
    var error: String? = nil

    // MARK: - Pipeline

    private let pipeline: QueryPipeline

    init(pipeline: QueryPipeline) {
        self.pipeline = pipeline
    }

    // MARK: - Public API

    func send() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        isSending = true
        defer { isSending = false }
        error = nil

        messages.append(.init(
            role: .user,
            text: trimmed,
            visualizationComponent: nil,
            filters: [:],
            entries: [],
            timeRange: nil,
            intentPlan: nil
        ))
        query = ""

        let fullPrompt: String
        if !extraContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fullPrompt = """
            Kontext:
            \(extraContext)

            Fråga:
            \(trimmed)
            """
        } else {
            fullPrompt = trimmed
        }

        do {
            let userQuery = UserQuery(text: fullPrompt, source: .userTyped)
            let result = try await pipeline.run(userQuery)
            let responseText = normalizedResponseText(from: result)
            messages.append(.init(
                role: .assistant,
                text: responseText,
                visualizationComponent: resolveVisualizationComponent(from: result.intentPlan),
                filters: result.intentPlan?.filters ?? [:],
                entries: result.entries,
                timeRange: result.timeRange,
                intentPlan: result.intentPlan
            ))
        } catch {
            self.error = error.localizedDescription
            messages.append(.init(
                role: .assistant,
                text: "Förlåt, något gick fel (\(error.localizedDescription)).",
                visualizationComponent: nil,
                filters: [:],
                entries: [],
                timeRange: nil,
                intentPlan: nil
            ))
        }
    }

    private func normalizedResponseText(from result: QueryResult) -> String {
        let trimmed = result.answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        if result.entries.isEmpty {
            return "Jag hittar ingen data att svara på ännu."
        }

        return "Jag hittade \(result.entries.count) poster. Kolla visualiseringen för detaljer."
    }

    private func resolveVisualizationComponent(from plan: BackendIntentPlanDTO?) -> VisualizationComponent? {
        guard
            let plan,
            let domain = mapDomain(plan.domain),
            let operation = mapOperation(plan.operation)
        else {
            return nil
        }

        if domain == .mail {
            return .narrative
        }

        let timeScope = mapTimeScope(plan.timeScope)
        return VisualizationPolicy.resolve(
            domain: domain,
            operation: operation,
            timeScope: timeScope
        )
    }

    private func mapDomain(_ domain: BackendIntentDomain?) -> Domain? {
        guard let domain else { return nil }

        switch domain {
        case .calendar:
            return .calendar
        case .reminders:
            return .reminders
        case .mail:
            return .mail
        case .contacts:
            return .contacts
        case .files:
            return .files
        case .photos:
            return .photos
        case .location:
            return .location
        case .notes:
            return .notes
        case .memory:
            return .memory
        }
    }

    private func mapOperation(_ operation: BackendIntentOperation) -> Operation? {
        switch operation {
        case .count:
            return .count
        case .list:
            return .list
        case .exists:
            return .exists
        case .sum, .sumDuration:
            return .sum
        case .latest:
            return .latest
        case .groupByDay, .groupByType, .needsClarification:
            return nil
        }
    }

    private func mapTimeScope(_ scope: BackendTimeScopeDTO) -> TimeScope {
        switch scope.type {
        case .all:
            return TimeScope(type: .all)
        case .absolute:
            return TimeScope(type: .absolute)
        case .relative:
            return TimeScope(type: .relative(scope.value ?? ""))
        }
    }
}
