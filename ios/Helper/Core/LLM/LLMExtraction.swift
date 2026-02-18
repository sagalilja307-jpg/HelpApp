//
//  LLMExtraction.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-27.
//


import Foundation

/// Parsed, safe output from the LLM.
/// This struct contains NO logic – only interpreted values.
struct LLMExtraction {

    /// High-level intent inferred by the LLM
    let intent: LLMIntent

    /// Confidence score from the LLM (0.0–1.0), if provided
    let confidence: Double?

    /// Optional date suggestion in ISO 8601 string form
    /// Example: "2026-03-14T10:00:00Z"
    let suggestedDateISO8601: String?
}

// MARK: - Helpers

extension LLMExtraction {

    /// Safely parses the ISO 8601 date string into a Date
    func parsedDate() -> Date? {
        guard let iso = suggestedDateISO8601 else { return nil }
        return DateService.shared.parseISO8601(iso)
    }
}
// MARK: - Builder bridging

extension LLMExtraction {

    /// Bridges LLMExtraction to the inputs expected by ActionSuggestionBuilder
    /// Maps LLMIntent to IntentType and parses the optional date.
    func toBuilderInput() -> (intent: IntentType, date: Date?) {
        return (
            intent: mapIntent(llmIntent: intent),
            date: parsedDate()
        )
    }

    /// Maps from the LLM-specific intent enum to the app's builder intent enum.
    private func mapIntent(llmIntent: LLMIntent) -> IntentType {
        switch llmIntent {
        case .calendar:
            return .calendar
        case .reminder:
            return .reminder
        case .note:
            return .note
        case .none:
            return .none
        case .ignore:
            return .none
        case .sendMessage:
            return .sendMessage
        }
    }
}
