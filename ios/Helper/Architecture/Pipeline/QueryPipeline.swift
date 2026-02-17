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
/// collect non-calendar deltas -> ingest -> backend query
/// and backend-driven calendar feature gating (one auto-retry max).
struct QueryPipeline {

    let interpreter: QueryInterpreting
    let access: QuerySourceAccessing
    let fetcher: QueryDataFetching
    let ingestService: AssistantIngesting
    let backendQueryService: BackendQuerying
    let checkpointStore: Etapp2IngestCheckpointStoring
    let sourceConnectionStore: SourceConnectionStoring
    let memoryService: MemoryService
    let featureStatusService: FeatureStatusFetching
    let calendarFeatureBuilder: CalendarFeatureBuilding
    let nowProvider: () -> Date

    init(
        interpreter: QueryInterpreting,
        access: QuerySourceAccessing,
        fetcher: QueryDataFetching,
        ingestService: AssistantIngesting,
        backendQueryService: BackendQuerying,
        checkpointStore: Etapp2IngestCheckpointStoring = NoOpEtapp2IngestCheckpointStore(),
        sourceConnectionStore: SourceConnectionStoring = SourceConnectionStore.shared,
        memoryService: MemoryService,
        featureStatusService: FeatureStatusFetching = NoOpFeatureStatusService(),
        calendarFeatureBuilder: CalendarFeatureBuilding = NoOpCalendarFeatureBuilder(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.interpreter = interpreter
        self.access = access
        self.fetcher = fetcher
        self.ingestService = ingestService
        self.backendQueryService = backendQueryService
        self.checkpointStore = checkpointStore
        self.sourceConnectionStore = sourceConnectionStore
        self.memoryService = memoryService
        self.featureStatusService = featureStatusService
        self.calendarFeatureBuilder = calendarFeatureBuilder
        self.nowProvider = nowProvider
    }
}

extension QueryPipeline {

    func run(_ query: UserQuery, lastBackendAnalyticsIntent: String? = nil) async throws -> QueryResult {
        let interpretation = try? await interpreter.interpret(query)
        let days = Self.inferredDays(for: query.text, interpretation: interpretation)

        if Self.isCalendarAnalyticsIntent(lastBackendAnalyticsIntent), access.isAllowed(.calendar) {
            let defaultWindow = Self.defaultCalendarIngestWindow(now: nowProvider())
            await proactivelyRefreshCalendarFeaturesIfNeeded(defaultWindow: defaultWindow)
        }

        // Determine if we should capture location (on-demand trigger)
        let shouldCaptureLocation = sourceConnectionStore.isEnabled(.location) && Self.isLocationIntent(query.text)
        let options = QueryCollectionOptions(
            shouldCaptureLocation: shouldCaptureLocation,
            includeCalendar: false,
            includeReminders: false
        )

        let collected = try await fetcher.collect(days: days, access: access, options: options)
        let missingPrefix = Self.missingAccessPrefix(for: collected.missingAccess)

        if !collected.items.isEmpty {
            try await ingestService.ingest(items: collected.items, features: nil)
            let context = memoryService.context()
            for source in collected.checkpointSources {
                try? checkpointStore.updateCheckpoint(for: source, at: Date(), in: context)
            }
        }

        var backendResponse = try await backendQueryService.query(
            text: query.text,
            days: days,
            sources: ["assistant_store"],
            dataFilter: nil
        )

        var calendarPermissionMessage: String?
        if Self.requiresCalendarFeatures(backendResponse) {
            if access.isAllowed(.calendar) {
                let requiredWindow = Self.requiredCalendarWindow(
                    from: backendResponse.requiredTimeWindow,
                    now: nowProvider()
                )
                try await ingestCalendarFeatures(for: requiredWindow)
                backendResponse = try await backendQueryService.query(
                    text: query.text,
                    days: days,
                    sources: ["assistant_store"],
                    dataFilter: nil
                )
            } else {
                calendarPermissionMessage = "Obs: Kalenderåtkomst saknas för den här analysen."
            }
        }

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
        if let calendarPermissionMessage, !calendarPermissionMessage.isEmpty {
            answer = "\(calendarPermissionMessage)\n\n\(answer)"
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
            answer: answer,
            backendAnalyticsIntent: backendResponse.analysis?.intentId
        )
    }

    private func proactivelyRefreshCalendarFeaturesIfNeeded(defaultWindow: DateInterval) async {
        do {
            let status = try await featureStatusService.fetchFeatureStatus()
            let calendar = status.calendar
            let shouldRefresh = Self.needsCalendarRefresh(
                calendar: calendar,
                requiredWindow: defaultWindow
            )
            if shouldRefresh {
                try await ingestCalendarFeatures(for: defaultWindow)
            }
        } catch {
            // Best effort only - query must still continue.
        }
    }

    private func ingestCalendarFeatures(for window: DateInterval) async throws {
        let events = try await calendarFeatureBuilder.buildFeatures(in: window)
        let features = IngestFeaturesDTO(calendarEvents: events)
        try await ingestService.ingest(items: [], features: features)
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
            messages.append("Obs: Kalenderåtkomst saknas")
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
            "var ar jag",
            "var är jag",
            "nara mig",
            "nära mig",
            "i narheten",
            "i närheten",
            "close to me",
            "near me",
            "where am i",
            "min plats",
            "nuvarande plats",
            "current location",
            "nearby",
            "around here",
            "har i narheten",
            "här i närheten",
            "vilken plats ar jag",
            "vilken plats är jag",
            "vad finns nara",
            "vad finns nära"
        ]
        return locationHints.contains { lower.contains($0) }
    }

    static func isCalendarAnalyticsIntent(_ intentId: String?) -> Bool {
        guard let intentId else { return false }
        return intentId.lowercased().hasPrefix("calendar.")
    }

    static func requiresCalendarFeatures(_ response: BackendLLMResponseDTO) -> Bool {
        let requires = response.requiresSources ?? []
        let needsCalendar = requires.contains { $0.lowercased() == "calendar" }
        let ready = response.analysisReady ?? true
        return needsCalendar && !ready
    }

    static func needsCalendarRefresh(
        calendar: BackendCalendarFeatureStatusDTO?,
        requiredWindow: DateInterval
    ) -> Bool {
        guard let calendar else { return true }
        if !calendar.available { return true }
        if !calendar.fresh { return true }

        guard let coverageStart = calendar.coverageStart,
              let coverageEnd = calendar.coverageEnd else {
            return true
        }

        // Calendar feature coverage is sparse; trigger refresh only if outside bounds.
        return requiredWindow.end < coverageStart || requiredWindow.start > coverageEnd
    }

    static func requiredCalendarWindow(from dto: BackendRequiredTimeWindowDTO?, now: Date) -> DateInterval {
        guard let dto else {
            return defaultCalendarIngestWindow(now: now)
        }
        return DateInterval(start: dto.start, end: dto.end)
    }

    static func defaultCalendarIngestWindow(now: Date) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -365, to: now) ?? now
        let end = calendar.date(byAdding: .day, value: 30, to: now) ?? now
        return DateInterval(start: start, end: end)
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

        _ = missingAccess
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

private struct NoOpFeatureStatusService: FeatureStatusFetching {
    func fetchFeatureStatus() async throws -> BackendFeatureStatusDTO {
        BackendFeatureStatusDTO(calendar: nil)
    }
}

private struct NoOpCalendarFeatureBuilder: CalendarFeatureBuilding {
    func buildFeatures(in interval: DateInterval) async throws -> [CalendarFeatureEventIngestDTO] {
        _ = interval
        return []
    }
}
