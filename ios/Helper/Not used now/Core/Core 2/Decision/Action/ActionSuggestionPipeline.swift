//
//  ActionSuggestionPipeline.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-27.
//


import Foundation

final class ActionSuggestionPipeline {

    private let builder = ActionSuggestionBuilder()
    private let classifier = ContentClassifier()
    private let llmExtractor = LLMActionExtractor()

    /// The single, calm question this pipeline answers:
    /// “Can a suggestion be constructed?”
    /// (NOT whether it should be shown.)
    func suggestAction(
        for content: ContentObject,
        policy: DecisionPolicy,
        clusterContext: ClusterContext? = nil
    ) async -> ActionSuggestion? {

        // 1️⃣ Heuristik-baserad intent
        let heuristicIntent = classifier.classify(content)

        if heuristicIntent != .none {
            return builder.buildSuggestion(
                from: content,
                intent: heuristicIntent,
                clusterContext: clusterContext
            )
        }

        // 2️⃣ LLM-baserad extraction, om tillåtet
        guard policy.allowLLM else {
            return nil
        }

        guard case .available = LLMAvailability.check() else {
            return nil
        }

        guard let extraction = try? await llmExtractor.extract(from: content) else {
            return nil
        }

        // 3️⃣ Confidence gate — lågt värde → inget förslag
        if let confidence = extraction.confidence, confidence < 0.4 {
            return nil
        }

        let input = extraction.toBuilderInput()

        // 4️⃣ Bygg ett konkret förslag (kan vara kalender, påminnelse etc.)
        return builder.buildSuggestion(
            from: content,
            intent: input.intent,
            dateHint: input.date,
            clusterContext: clusterContext,
            confidence: extraction.confidence
        )
    }
}
