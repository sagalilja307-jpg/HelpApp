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
        let interpretationHint: String?
        let clarificationDomains: [BackendIntentDomain]
        let submittedQuery: String?
        let timestamp: Date = .now
    }

    // MARK: - UI-state

    var messages: [ChatMessage] = []
    var query: String = ""
    var isSending = false
    var error: String? = nil

    // MARK: - Pipeline

    private let pipeline: QueryPipeline

    init(pipeline: QueryPipeline) {
        self.pipeline = pipeline
    }

    // MARK: - Public API

    func send(_ submittedText: String? = nil) async {
        let trimmed = (submittedText ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
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
            intentPlan: nil,
            interpretationHint: nil,
            clarificationDomains: [],
            submittedQuery: trimmed
        ))
        query = ""

        do {
            let userQuery = UserQuery(text: trimmed, source: .userTyped)
            let result = try await pipeline.run(userQuery)
            let responseText = normalizedResponseText(from: result)
            messages.append(.init(
                role: .assistant,
                text: responseText,
                visualizationComponent: resolveVisualizationComponent(from: result.intentPlan),
                filters: result.intentPlan?.filters ?? [:],
                entries: result.entries,
                timeRange: result.timeRange,
                intentPlan: result.intentPlan,
                interpretationHint: interpretationHint(from: result.intentPlan),
                clarificationDomains: clarificationDomains(from: result.intentPlan),
                submittedQuery: trimmed
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
                intentPlan: nil,
                interpretationHint: nil,
                clarificationDomains: [],
                submittedQuery: trimmed
            ))
        }
    }

    func sendClarification(for message: ChatMessage, domain: BackendIntentDomain) async {
        guard let originalQuery = message.submittedQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
              !originalQuery.isEmpty else {
            return
        }
        await send(clarifiedQuery(from: originalQuery, domain: domain))
    }

    func clarifiedQuery(from originalQuery: String, domain: BackendIntentDomain) -> String {
        let trimmed = originalQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let suffix: String
        switch domain {
        case .calendar:
            suffix = "i kalendern"
        case .mail:
            suffix = "i mejlen"
        case .reminders:
            suffix = "i påminnelser"
        case .notes:
            suffix = "i anteckningarna"
        case .files:
            suffix = "i filerna"
        case .photos:
            suffix = "i bilderna"
        case .contacts:
            suffix = "i kontakterna"
        case .location:
            suffix = "i platshistoriken"
        case .memory:
            suffix = "i minnet"
        case .health:
            suffix = "i hälsodatan"
        }

        let normalized = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let normalizedSuffix = suffix
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        if normalized.contains(normalizedSuffix) {
            return trimmed
        }

        if trimmed.hasSuffix("?") {
            return "\(trimmed.dropLast()) \(suffix)?"
        }
        return "\(trimmed) \(suffix)"
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
        case .health:
            return .health
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

    private func clarificationDomains(from plan: BackendIntentPlanDTO?) -> [BackendIntentDomain] {
        guard let plan else { return [] }
        return QueryPipeline.candidateDomains(from: plan)
    }

    private func interpretationHint(from plan: BackendIntentPlanDTO?) -> String? {
        guard let plan,
              !plan.needsClarification,
              let domain = plan.domain else {
            return nil
        }

        var parts: [String] = ["Tolkat som \(localizedDomain(domain))"]

        if let qualifier = interpretationQualifier(from: plan) {
            parts.append(qualifier)
        }

        return parts.joined(separator: " · ")
    }

    private func interpretationQualifier(from plan: BackendIntentPlanDTO) -> String? {
        if let status = plan.filters["status"]?.value as? String {
            switch status {
            case "unread":
                return "olästa"
            case "pending":
                return "öppna"
            case "completed":
                return "klara"
            case "cancelled":
                return "inställda"
            default:
                break
            }
        }

        if let participants = plan.filters["participants"]?.value as? [Any],
           let first = participants.first as? String,
           !first.isEmpty {
            if plan.domain == .mail {
                return "från \(first.capitalized)"
            }
            if plan.domain == .contacts {
                return first.capitalized
            }
        }

        if let locationQualifier = locationQualifier(from: plan) {
            return locationQualifier
        }

        if let healthQualifier = healthQualifier(from: plan) {
            return healthQualifier
        }

        if let textContains = plan.filters["text_contains"]?.value as? String,
           !textContains.isEmpty,
           plan.domain == .files || plan.domain == .photos || plan.domain == .notes || plan.domain == .memory {
            return textContains
        }

        if let hasAttachment = plan.filters["has_attachment"]?.value as? Bool, hasAttachment {
            return "med bilagor"
        }

        if let timeLabel = localizedTimeScope(plan.timeScope) {
            return timeLabel
        }

        return nil
    }

    private func locationQualifier(from plan: BackendIntentPlanDTO) -> String? {
        guard plan.domain == .location else { return nil }

        let locationName = (plan.filters["location"]?.value as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayLocation: String?
        if let locationName, !locationName.isEmpty {
            displayLocation = locationName.capitalized
        } else {
            displayLocation = nil
        }

        return combinedQualifier(primary: displayLocation, secondary: localizedTimeScope(plan.timeScope))
    }

    private func healthQualifier(from plan: BackendIntentPlanDTO) -> String? {
        guard plan.domain == .health else { return nil }

        let workoutType = plan.filters["workout_type"]?.value as? String
        let metric = plan.filters["metric"]?.value as? String
        let metricLabel = localizedHealthLabel(metric: metric, workoutType: workoutType)

        return combinedQualifier(primary: metricLabel, secondary: localizedTimeScope(plan.timeScope))
    }

    private func combinedQualifier(primary: String?, secondary: String?) -> String? {
        let values: [String] = [primary, secondary].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: " · ")
    }

    private func localizedHealthLabel(metric: String?, workoutType: String?) -> String? {
        if let workoutType {
            switch workoutType {
            case "running":
                return "löpning"
            case "cycling":
                return "cykling"
            case "strength":
                return "styrka"
            default:
                break
            }
        }

        switch metric {
        case "step_count":
            return "steg"
        case "distance":
            return "distans"
        case "exercise_time":
            return "träningstid"
        case "workout":
            return "träning"
        case "sleep":
            return "sömn"
        case "mindful_session":
            return "mindfulness"
        case "state_of_mind":
            return "mående"
        case "heart_rate":
            return "puls"
        case "resting_heart_rate":
            return "vilopuls"
        case "hrv":
            return "HRV"
        case "respiratory_rate":
            return "andning"
        case "blood_oxygen":
            return "blodsyre"
        default:
            return nil
        }
    }

    private func localizedTimeScope(_ scope: BackendTimeScopeDTO) -> String? {
        switch scope.type {
        case .all:
            return nil
        case .absolute:
            if scope.start != nil || scope.end != nil {
                return "vald period"
            }
            return nil
        case .relative:
            switch scope.value {
            case "today":
                return "idag"
            case "today_morning":
                return "i morse"
            case "today_day":
                return "idag"
            case "today_afternoon":
                return "i eftermiddag"
            case "today_evening":
                return "ikväll"
            case "tomorrow":
                return "imorgon"
            case "tomorrow_morning":
                return "imorgon bitti"
            case "yesterday":
                return "igår"
            case "this_week":
                return "den här veckan"
            case "last_week":
                return "förra veckan"
            case "7d":
                return "senaste 7 dagarna"
            case "30d":
                return "senaste 30 dagarna"
            case "3m":
                return "senaste 3 månaderna"
            case "1y":
                return "senaste året"
            case "this_month":
                return "den här månaden"
            case "next_week":
                return "nästa vecka"
            case "next_month":
                return "nästa månad"
            default:
                return nil
            }
        }
    }

    private func localizedDomain(_ domain: BackendIntentDomain) -> String {
        switch domain {
        case .calendar:
            return "kalender"
        case .reminders:
            return "påminnelser"
        case .mail:
            return "mejl"
        case .contacts:
            return "kontakter"
        case .files:
            return "filer"
        case .photos:
            return "bilder"
        case .location:
            return "plats"
        case .notes:
            return "anteckningar"
        case .memory:
            return "minne"
        case .health:
            return "hälsa"
        }
    }
}
