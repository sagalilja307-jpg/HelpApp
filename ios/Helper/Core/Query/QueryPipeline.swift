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
/// interpret (helper only) → collect data → ingest → backend query
struct QueryPipeline {

    let interpreter: QueryInterpreting
    let access: QuerySourceAccessing
    let fetcher: QueryDataFetching
    let ingestService: AssistantIngesting
    let backendQueryService: BackendQuerying

    init(
        interpreter: QueryInterpreting,
        access: QuerySourceAccessing,
        fetcher: QueryDataFetching,
        ingestService: AssistantIngesting,
        backendQueryService: BackendQuerying
    ) {
        self.interpreter = interpreter
        self.access = access
        self.fetcher = fetcher
        self.ingestService = ingestService
        self.backendQueryService = backendQueryService
    }
}

extension QueryPipeline {

    func run(_ query: UserQuery) async throws -> QueryResult {
        let interpretation = try? await interpreter.interpret(query)
        let days = Self.inferredDays(for: query.text, interpretation: interpretation)

        let collected = try await fetcher.collect(days: days, access: access)
        let missingPrefix = Self.missingAccessPrefix(for: collected.missingAccess)

        guard !collected.items.isEmpty else {
            let emptyMessage = "Jag hittar ingen data att svara på ännu."
            let answer = missingPrefix.isEmpty ? emptyMessage : "\(missingPrefix)\n\n\(emptyMessage)"

            return QueryResult(
                timeRange: collected.timeRange,
                entries: collected.entries,
                answer: answer
            )
        }

        try await ingestService.ingest(items: collected.items)
        let backendResponse = try await backendQueryService.query(
            text: query.text,
            days: days,
            sources: ["assistant_store"],
            dataFilter: nil
        )

        var answer = backendResponse.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if answer.isEmpty {
            answer = "Jag hittar ingen data att svara på ännu."
        }

        if !missingPrefix.isEmpty {
            answer = "\(missingPrefix)\n\n\(answer)"
        }

        let mappedEntries = mapEvidenceEntries(from: backendResponse.evidenceItems)
        let entries = mappedEntries.isEmpty ? collected.entries : mappedEntries

        return QueryResult(
            timeRange: backendResponse.timeRange.map {
                DateInterval(start: $0.start, end: $0.end)
            } ?? collected.timeRange,
            entries: entries,
            answer: answer
        )
    }

    private func mapEvidenceEntries(from evidence: [EvidenceItemDTO]?) -> [QueryResult.Entry] {
        guard let evidence, !evidence.isEmpty else { return [] }

        return evidence.map { item in
            QueryResult.Entry(
                id: UUID(uuidString: item.id) ?? UUID(),
                source: Self.mapSource(item.source),
                title: item.title,
                body: item.body.isEmpty ? nil : item.body,
                date: item.date
            )
        }
    }

    private static func mapSource(_ source: String) -> QuerySource {
        switch source.lowercased() {
        case "calendar":
            return .calendar
        case "reminders":
            return .reminders
        case "notes":
            return .memory
        default:
            return .rawEvents
        }
    }

    private static func missingAccessPrefix(for missing: [QuerySource]) -> String {
        var messages: [String] = []

        if missing.contains(.calendar) {
            messages.append("Obs: Kalenderatkomst saknas")
        }
        if missing.contains(.reminders) {
            messages.append("Obs: Paminnelseatkomst saknas")
        }

        return messages.joined(separator: "\n")
    }

    private static func inferredDays(for text: String, interpretation: QueryInterpretation?) -> Int {
        let lower = text.lowercased()
        let shortRangeHints = [
            "idag",
            "imorgon",
            "denna vecka",
            "veckan",
            "today",
            "tomorrow",
            "this week"
        ]

        if shortRangeHints.contains(where: lower.contains) {
            return 7
        }

        if interpretation?.intent == .overview {
            return 7
        }

        return 90
    }
}
