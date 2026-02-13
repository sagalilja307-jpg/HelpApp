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
    let checkpointStore: Etapp2IngestCheckpointStoring
    let sourceConnectionStore: SourceConnectionStoring

    init(
        interpreter: QueryInterpreting,
        access: QuerySourceAccessing,
        fetcher: QueryDataFetching,
        ingestService: AssistantIngesting,
        backendQueryService: BackendQuerying,
        checkpointStore: Etapp2IngestCheckpointStoring = NoOpEtapp2IngestCheckpointStore(),
        sourceConnectionStore: SourceConnectionStoring = SourceConnectionStore.shared
    ) {
        self.interpreter = interpreter
        self.access = access
        self.fetcher = fetcher
        self.ingestService = ingestService
        self.backendQueryService = backendQueryService
        self.checkpointStore = checkpointStore
        self.sourceConnectionStore = sourceConnectionStore
    }
}

extension QueryPipeline {

    func run(_ query: UserQuery) async throws -> QueryResult {
        let interpretation = try? await interpreter.interpret(query)
        let days = Self.inferredDays(for: query.text, interpretation: interpretation)

        // Determine if we should capture location (on-demand trigger)
        let shouldCaptureLocation = sourceConnectionStore.isEnabled(.location) && Self.isLocationIntent(query.text)
        let options = QueryCollectionOptions(shouldCaptureLocation: shouldCaptureLocation)

        let collected = try await fetcher.collect(days: days, access: access, options: options)
        let missingPrefix = Self.missingAccessPrefix(for: collected.missingAccess)

        if !collected.items.isEmpty {
            try await ingestService.ingest(items: collected.items)
            for source in collected.checkpointSources {
                try? checkpointStore.updateCheckpoint(for: source, at: Date())
            }
        }
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

        // Add location uncertainty prefix if location evidence was used
        let locationPrefix = Self.locationUncertaintyPrefix(
            usedSources: backendResponse.usedSources ?? [],
            collected: collected,
            missingAccess: collected.missingAccess
        )
        if !locationPrefix.isEmpty {
            answer = "\(locationPrefix)\n\n\(answer)"
        }

        if !missingPrefix.isEmpty {
            answer = "\(missingPrefix)\n\n\(answer)"
        }

        let mappedEntries = mapEvidenceEntries(from: backendResponse.evidenceItems)
        let entries = mappedEntries.isEmpty ? collected.entries : mappedEntries

        if entries.isEmpty, answer.isEmpty {
            answer = "Jag hittar ingen data att svara på ännu."
        }

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
        case "contacts":
            return .contacts
        case "photos":
            return .photos
        case "files":
            return .files
        case "locations", "location":
            return .location
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
        if missing.contains(.contacts) {
            messages.append("Obs: Kontaktatkomst saknas")
        }
        if missing.contains(.photos) {
            messages.append("Obs: Bildatkomst saknas")
        }
        if missing.contains(.files) {
            messages.append("Obs: Ingen importerad fil-data hittades")
        }
        if missing.contains(.location) {
            messages.append("Obs: Platsåtkomst saknas")
        }

        return messages.joined(separator: "\n")
    }

    /// Detect if query has location intent
    static func isLocationIntent(_ text: String) -> Bool {
        let lower = text.lowercased()
        let locationHints = [
            "var är jag",
            "nära mig",
            "i närheten",
            "close to me",
            "near me",
            "where am i",
            "min plats",
            "nuvarande plats",
            "current location",
            "nearby",
            "around here",
            "här i närheten"
        ]
        return locationHints.contains { lower.contains($0) }
    }

    /// Generate location uncertainty prefix based on usage
    private static func locationUncertaintyPrefix(
        usedSources: [String],
        collected: QueryCollectedData,
        missingAccess: [QuerySource]
    ) -> String {
        let locationUsed = usedSources.contains { $0.lowercased() == "locations" }
        let hasLocationEntries = collected.entries.contains { $0.source == .location }

        if locationUsed || hasLocationEntries {
            if collected.locationFallbackUsed {
                return "Obs: Platsdata är ungefärlig och kan vara inaktuell (använder tidigare uppmätt plats)."
            }
            return "Obs: Platsdata är ungefärlig och kan vara inaktuell."
        }

        return ""
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
