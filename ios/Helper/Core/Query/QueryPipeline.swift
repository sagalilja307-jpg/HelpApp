import Foundation

// ===============================================================
// File: Helper/Core/Query/QueryPipeline.swift
// ===============================================================

enum QueryPipelineError: Error, LocalizedError, Sendable {
    case sourceNotAllowed(QuerySource, String)

    var errorDescription: String? {
        switch self {
        case let .sourceNotAllowed(source, reason):
            return "Åtkomst nekad till \(source.rawValue): \(reason)"
        }
    }
}

/// Orchestrates the full query flow:
/// interpret → access check → fetch → compose
struct QueryPipeline: Sendable {

    let interpreter: QueryInterpreter
    let access: QuerySourceAccess
    let fetcher: QueryDataFetcher
    let composer: QueryAnswerComposer

    init(
        interpreter: QueryInterpreter,
        access: QuerySourceAccess,
        fetcher: QueryDataFetcher,
        composer: QueryAnswerComposer
    ) {
        self.interpreter = interpreter
        self.access = access
        self.fetcher = fetcher
        self.composer = composer
    }
}

extension QueryPipeline {

    func run(_ query: UserQuery) async throws -> QueryResult {

        // 1️⃣ Interpret the query (what does the user want?)
        let interpretation = try await interpreter.interpret(query)

        // 2️⃣ Enforce data access rules (memory, calendar, etc)
        for source in interpretation.requiredSources {
            try access.assertAllowed(source)
        }

        // 3️⃣ Fetch the required data
        let fetched = try await fetcher.fetch(for: interpretation)

        // 4️⃣ Compose final answer
        return try await composer.compose(
            result: fetched,
            interpretation: interpretation
        )
    }
}
