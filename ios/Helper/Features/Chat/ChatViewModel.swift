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
        let id: UUID
        let role: Role
        let text: String
        let visualizationComponent: VisualizationComponent?
        let filters: [String: AnyCodable]
        let entries: [QueryResult.Entry]
        let timeRange: DateInterval?
        let intentPlan: BackendIntentPlanDTO?
        let interpretationHint: String?
        let suggestion: ChatSuggestionCard?
        let clarificationDomains: [BackendIntentDomain]
        let submittedQuery: String?
        let timestamp: Date

        init(
            id: UUID = UUID(),
            role: Role,
            text: String,
            visualizationComponent: VisualizationComponent?,
            filters: [String: AnyCodable],
            entries: [QueryResult.Entry],
            timeRange: DateInterval?,
            intentPlan: BackendIntentPlanDTO?,
            interpretationHint: String?,
            suggestion: ChatSuggestionCard?,
            clarificationDomains: [BackendIntentDomain],
            submittedQuery: String?,
            timestamp: Date = .now
        ) {
            self.id = id
            self.role = role
            self.text = text
            self.visualizationComponent = visualizationComponent
            self.filters = filters
            self.entries = entries
            self.timeRange = timeRange
            self.intentPlan = intentPlan
            self.interpretationHint = interpretationHint
            self.suggestion = suggestion
            self.clarificationDomains = clarificationDomains
            self.submittedQuery = submittedQuery
            self.timestamp = timestamp
        }

        func updating(suggestion: ChatSuggestionCard?) -> ChatMessage {
            ChatMessage(
                id: id,
                role: role,
                text: text,
                visualizationComponent: visualizationComponent,
                filters: filters,
                entries: entries,
                timeRange: timeRange,
                intentPlan: intentPlan,
                interpretationHint: interpretationHint,
                suggestion: suggestion,
                clarificationDomains: clarificationDomains,
                submittedQuery: submittedQuery,
                timestamp: timestamp
            )
        }
    }

    // MARK: - UI-state

    var messages: [ChatMessage] = []
    var query: String = ""
    var isSending = false
    var error: String? = nil

    // MARK: - Pipeline

    private let pipeline: QueryPipeline
    private let suggestionEngine: ChatSuggestionEvaluating
    private let suggestionLogger: ChatSuggestionLogging

    init(
        pipeline: QueryPipeline,
        suggestionEngine: ChatSuggestionEvaluating? = nil,
        suggestionLogger: ChatSuggestionLogging? = nil
    ) {
        self.pipeline = pipeline
        self.suggestionEngine = suggestionEngine ?? ChatSuggestionEngine()
        self.suggestionLogger = suggestionLogger ?? NoopChatSuggestionLogger()
    }

    // MARK: - Public API

    func send(_ submittedText: String? = nil) async {
        let trimmed = (submittedText ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        isSending = true
        defer { isSending = false }
        error = nil
        let clarificationContext = clarificationContextForNextTurn()

        let userMessage = ChatMessage(
            role: .user,
            text: trimmed,
            visualizationComponent: nil,
            filters: [:],
            entries: [],
            timeRange: nil,
            intentPlan: nil,
            interpretationHint: nil,
            suggestion: nil,
            clarificationDomains: [],
            submittedQuery: trimmed
        )
        messages.append(userMessage)
        query = ""

        let suggestionDecision = suggestionEngine.decide(for: trimmed)

        if let immediateSuggestion = immediateAssistantSuggestion(from: suggestionDecision) {
            let assistantMessage = ChatMessage(
                role: .assistant,
                text: immediateSuggestion.message,
                visualizationComponent: nil,
                filters: [:],
                entries: [],
                timeRange: nil,
                intentPlan: nil,
                interpretationHint: nil,
                suggestion: immediateSuggestion.card,
                clarificationDomains: [],
                submittedQuery: trimmed
            )
            messages.append(assistantMessage)
            logSuggestionDecision(
                suggestionDecision,
                userMessageID: userMessage.id.uuidString,
                assistantMessageID: assistantMessage.id.uuidString
            )
            return
        }

        do {
            let userQuery = UserQuery(
                text: trimmed,
                source: .userTyped,
                clarificationContext: clarificationContext
            )
            let result = try await pipeline.run(userQuery)
            let responseText = normalizedResponseText(from: result)
            let assistantMessage = ChatMessage(
                role: .assistant,
                text: responseText,
                visualizationComponent: resolveVisualizationComponent(from: result.intentPlan),
                filters: result.intentPlan?.filters ?? [:],
                entries: result.entries,
                timeRange: result.timeRange,
                intentPlan: result.intentPlan,
                interpretationHint: interpretationHint(from: result.intentPlan),
                suggestion: suggestion(from: suggestionDecision),
                clarificationDomains: clarificationDomains(from: result.intentPlan),
                submittedQuery: trimmed
            )
            messages.append(assistantMessage)
            logSuggestionDecision(
                suggestionDecision,
                userMessageID: userMessage.id.uuidString,
                assistantMessageID: assistantMessage.id.uuidString
            )
        } catch {
            self.error = error.localizedDescription
            let assistantMessage = ChatMessage(
                role: .assistant,
                text: "Förlåt, något gick fel (\(error.localizedDescription)).",
                visualizationComponent: nil,
                filters: [:],
                entries: [],
                timeRange: nil,
                intentPlan: nil,
                interpretationHint: nil,
                suggestion: suggestion(from: suggestionDecision),
                clarificationDomains: [],
                submittedQuery: trimmed
            )
            messages.append(assistantMessage)
            logSuggestionDecision(
                suggestionDecision,
                userMessageID: userMessage.id.uuidString,
                assistantMessageID: assistantMessage.id.uuidString
            )
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

    func dismissSuggestion(for messageID: UUID) {
        guard let message = message(withID: messageID), let suggestion = message.suggestion else {
            return
        }
        transitionSuggestionState(for: messageID, event: .dismiss)
        suggestionLogger.log(
            action: .dismissed,
            messageID: messageID.uuidString,
            kind: suggestion.kind,
            confidence: suggestion.confidence,
            reasons: suggestion.auditReasons
        )
    }

    func markSuggestionExecuting(for messageID: UUID) {
        transitionSuggestionState(for: messageID, event: .beginExecution)
    }

    func restoreSuggestionVisible(for messageID: UUID) {
        transitionSuggestionState(for: messageID, event: .restoreApproval)
    }

    func completeSuggestion(
        for messageID: UUID,
        logging action: DecisionAction? = .executed
    ) {
        guard let message = message(withID: messageID), let suggestion = message.suggestion else {
            return
        }
        transitionSuggestionState(for: messageID, event: .complete)
        guard let action else { return }
        suggestionLogger.log(
            action: action,
            messageID: messageID.uuidString,
            kind: suggestion.kind,
            confidence: suggestion.confidence,
            reasons: suggestion.auditReasons
        )
    }

    func failSuggestion(for messageID: UUID, message: String) {
        transitionSuggestionState(for: messageID, event: .fail(message))
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

    private func clarificationContextForNextTurn() -> BackendQueryClarificationContextDTO? {
        guard let lastAssistant = messages.last, lastAssistant.role == .assistant else {
            return nil
        }
        guard !lastAssistant.clarificationDomains.isEmpty else {
            return nil
        }
        guard let originalQuery = lastAssistant.submittedQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
              !originalQuery.isEmpty else {
            return nil
        }

        return BackendQueryClarificationContextDTO(
            originalQuery: originalQuery,
            candidateDomains: lastAssistant.clarificationDomains
        )
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
        if let workQualifier = workQualifier(from: plan) {
            return workQualifier
        }

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

    private func workQualifier(from plan: BackendIntentPlanDTO) -> String? {
        guard plan.domain == .calendar else { return nil }
        guard let semanticIntent = plan.filters["semantic_intent"]?.value as? String,
              semanticIntent.hasPrefix("work") else {
            return nil
        }
        return combinedQualifier(primary: "jobb", secondary: localizedTimeScope(plan.timeScope))
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

    private func suggestion(from decision: ChatSuggestionDecision) -> ChatSuggestionCard? {
        guard case .suggestion(let suggestion) = decision else {
            return nil
        }
        return suggestion
    }

    private func logSuggestionDecision(
        _ decision: ChatSuggestionDecision,
        userMessageID: String,
        assistantMessageID: String
    ) {
        switch decision {
        case .suggestion(let suggestion):
            suggestionLogger.log(
                action: .suggested,
                messageID: assistantMessageID,
                kind: suggestion.kind,
                confidence: suggestion.confidence,
                reasons: suggestion.auditReasons
            )
        case .suppressed(let kind, let confidence, let reasons):
            suggestionLogger.log(
                action: .suppressed,
                messageID: userMessageID,
                kind: kind,
                confidence: confidence,
                reasons: reasons
            )
        case .noAction(let reasons):
            suggestionLogger.log(
                action: .noAction,
                messageID: userMessageID,
                kind: nil,
                confidence: nil,
                reasons: reasons
            )
        }
    }

    private func updateSuggestion(
        for messageID: UUID,
        transform: (ChatSuggestionCard) -> ChatSuggestionCard
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              let suggestion = messages[index].suggestion else {
            return
        }
        messages[index] = messages[index].updating(suggestion: transform(suggestion))
    }

    private func transitionSuggestionState(
        for messageID: UUID,
        event: ActionConfirmationEvent
    ) {
        updateSuggestion(for: messageID) { suggestion in
            let nextState = ActionConfirmationFlow.transition(
                from: ActionConfirmationState(suggestion.state),
                event: event
            )
            return suggestion.updating(state: ChatSuggestionState(nextState))
        }
    }

    private func message(withID id: UUID) -> ChatMessage? {
        messages.first(where: { $0.id == id })
    }

    private func immediateAssistantSuggestion(
        from decision: ChatSuggestionDecision
    ) -> (card: ChatSuggestionCard, message: String)? {
        guard case .suggestion(let suggestion) = decision else {
            return nil
        }

        if suggestion.kind == .calendar,
           suggestion.auditReasons.contains("intent:create_request") {
            return (
                card: suggestion,
                message: "Jag kan lägga in det här i kalendern. Vill du öppna utkastet?"
            )
        }

        if suggestion.kind == .followUp,
           suggestion.auditReasons.contains("intent:follow_up_request") {
            return (
                card: suggestion,
                message: "Jag kan lägga upp en uppföljning åt dig. Vill du öppna utkastet?"
            )
        }

        return nil
    }
}
