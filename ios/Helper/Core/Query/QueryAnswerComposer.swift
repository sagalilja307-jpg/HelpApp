import Foundation

// ===============================================================
// File: Helper/Core/Query/QueryAnswerComposer.swift
// ===============================================================

final class QueryAnswerComposer {

    private let llm: LLMClient

    init(llm: LLMClient = LLMClient()) {
        self.llm = llm
    }

    func compose(
        result: QueryResult,
        interpretation: QueryInterpretation
    ) async throws -> QueryResult {

        var newResult = result

        let prompt = buildPrompt(
            result: result,
            interpretation: interpretation
        )

        let generatedText = try await llm.respond(to: prompt)

        newResult.answer = generatedText
        return newResult
    }
}

// MARK: - Prompt construction

private extension QueryAnswerComposer {

    func buildPrompt(
        result: QueryResult,
        interpretation: QueryInterpretation
    ) -> String {

        let entriesText = result.entries
            .map { entry in
                """
                [\(entry.source.rawValue)]
                \(entry.title)
                \(entry.body ?? "")
                """
            }
            .joined(separator: "\n\n")

        return """
        You are a helpful assistant.
        Answer the user's query using ONLY the information provided below.
        If information is missing, say so clearly.

        Intent: \(interpretation.intent.rawValue)

        Data:
        \(entriesText)

        Answer:
        """
    }
}
