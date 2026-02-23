//
//  LLMActionExtractor.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-27.
//


import Foundation

final class LLMActionExtractor {

    private let client: LLMClient

    public init(client: LLMClient = LLMClient()) {
        self.client = client
    }


    func extract(from content: ContentObject) async throws -> LLMExtraction {

        let prompt = """
        You are a calm, supportive assistant.

        Analyze the content and extract:
        - intent (calendar, reminder, note, none)
        - suggestedDate (only if clearly implied)
        - confidence (0.0–1.0)

        Content:
        "\(content.rawText)"
        """

        // Placeholder: replace with guided generation call
        _ = try await client.respond(to: prompt)

        throw NSError(
            domain: "LLMActionExtractor",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Guided generation not yet connected"]
        )
    }
}
