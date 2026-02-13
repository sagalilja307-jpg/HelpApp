import Foundation

protocol QueryInterpreting {
    func interpret(_ query: UserQuery) async throws -> QueryInterpretation
}

final class QueryInterpreter: QueryInterpreting {

    private let llm: LLMClient

    init(llm: LLMClient = LLMClient()) {
        self.llm = llm
    }

    func interpret(_ query: UserQuery) async throws -> QueryInterpretation {

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let meta = QueryInterpretationRequest(
            text: query.text,
            createdAt: query.createdAt,
            source: query.source.rawValue
        )

        let metaJSON = String(
            data: try encoder.encode(meta),
            encoding: .utf8
        ) ?? "{}"

        let prompt = """
        You are a query interpreter.
        You do NOT answer questions.
        Return ONLY valid JSON.

        UserQueryMeta:
        \(metaJSON)

        The JSON MUST match this schema:
        {
          "intent": "summary | recall | overview | memoryLookup | unknown",
          "requiredSources": ["memory", "calendar", "reminders", "rawEvents"],
          "confidence": 0.0
        }
        """

        let raw = try await llm.respond(to: prompt)
        return Self.parseInterpretation(from: raw)
    }
}

// MARK: - DTOs

private struct QueryInterpretationRequest: Codable, Sendable {
    let text: String
    let createdAt: Date
    let source: String
}

private struct QueryInterpretationDTO: Codable {
    let intent: QueryIntent
    let requiredSources: [QuerySource]
    let confidence: Double?
}

// MARK: - Parsing

private extension QueryInterpreter {

    static func parseInterpretation(from raw: String) -> QueryInterpretation {

        let data = Data(raw.utf8)

        guard let dto = try? JSONDecoder().decode(
            QueryInterpretationDTO.self,
            from: data
        ) else {
            // Safe fallback: assume memory-only, unknown intent
            return QueryInterpretation(
                intent: .unknown,
                requiredSources: [.memory],
                timeRange: nil,
                confidence: nil
            )
        }

        return QueryInterpretation(
            intent: dto.intent,
            requiredSources: dto.requiredSources,
            timeRange: nil,
            confidence: dto.confidence
        )
    }
}
