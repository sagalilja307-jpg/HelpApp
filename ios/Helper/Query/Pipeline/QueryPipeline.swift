import Foundation

/// Transport-only pipeline:
/// - iOS skickar bara query
/// - backend returnerar intent_plan
/// - iOS väljer *en* källa, gör access-gate, fetchar lokalt via QueryDataFetcher
///
/// OBS:
/// Jag har skrivit detta som en “riktig pipeline” (backend plan -> access -> local fetch).
/// Eftersom jag inte kan se exakt signatures på dina typer i hela projektet här,
/// har jag gjort två saker för att minimera friktion:
///   1) Jag injicerar en liten `LocalQueryCollecting`-abstraktion som du enkelt kan adaptera
///      runt din befintliga `QueryDataFetcher`.
///   2) Jag använder `QuerySourceAccessChecking` för access-gate (adapter runt QuerySourceAccess + SourceConnectionStore).
///
/// Du kan behålla exakt logik och bara koppla adapters i composition root.
struct QueryPipeline {

    let backendQueryService: BackendQuerying
    let localCollector: LocalQueryCollecting
    let accessGate: QuerySourceAccessChecking

    init(
        backendQueryService: BackendQuerying,
        localCollector: LocalQueryCollecting,
        accessGate: QuerySourceAccessChecking
    ) {
        self.backendQueryService = backendQueryService
        self.localCollector = localCollector
        self.accessGate = accessGate
    }

    func run(_ query: UserQuery) async throws -> QueryResult {
        // 0) Backend call with graceful error handling
        let response: BackendQueryResponseDTO
        do {
            response = try await backendQueryService.query(text: query.text)
        } catch {
            return QueryResult(
                timeRange: nil,
                entries: [],
                answer: "Förlåt, kunde inte kontakta servern: \(error.localizedDescription)",
                intentPlan: nil
            )
        }
        let plan = response.intentPlan

        if plan.domain == .mail && !response.hasDataIntent {
            return QueryResult(
                timeRange: nil,
                entries: [],
                answer: response.answer ?? "Jag kunde inte tolka mejlfrågan ännu.",
                intentPlan: nil
            )
        }

        // 1) Clarification flow (källa)
        if plan.needsClarification || plan.domain == nil {
            return QueryResult(
                timeRange: nil,
                entries: [],
                answer: Self.clarificationMessage(from: plan),
                intentPlan: plan
            )
        }

        // 2) Domain -> QuerySource (MVP: alla utom memory/mail)
        guard let source = Self.mapDomainToSource(plan.domain) else {
            let domain = plan.domain?.rawValue ?? "okänd"
            return QueryResult(
                timeRange: nil,
                entries: [],
                answer: "Jag kan inte hämta data för \"\(domain)\" än.",
                intentPlan: plan
            )
        }

        // 3) Time range (du sa att datafetcher redan kan tid)
        let timeRange: DateInterval? = {
            guard let start = plan.timeScope.start, let end = plan.timeScope.end else { return nil }
            return DateInterval(start: start, end: end)
        }()

        // 4) Access gate (din regel: stoppa direkt om saknas)
        if !accessGate.isEnabled(source) {
            return QueryResult(
                timeRange: timeRange,
                entries: [],
                answer: "Källan \(Self.localizedSource(source)) är inte aktiverad.",
                intentPlan: plan
            )
        }
        if !accessGate.isAllowed(source) {
            return QueryResult(
                timeRange: timeRange,
                entries: [],
                answer: accessGate.deniedMessage(for: source) ?? "Jag har inte access till \(Self.localizedSource(source)).",
                intentPlan: plan
            )
        }

        // 5) Local fetch (en källa i taget)
        let collected: LocalCollectedResult
        do {
            collected = try await localCollector.collect(
                source: source,
                timeRange: timeRange,
                intentPlan: plan,
                userQuery: query
            )
        } catch {
            return QueryResult(
                timeRange: timeRange,
                entries: [],
                answer: "Kunde inte hämta data lokalt: \(error.localizedDescription)",
                intentPlan: plan
            )
        }

        // 6) Operation (MVP: backend skickar count; vi bygger deterministiskt svar lokalt)
        let answer = Self.buildAnswer(plan: plan, collected: collected, source: source, timeRange: timeRange)

        return QueryResult(
            timeRange: timeRange,
            entries: collected.entries,
            answer: answer,
            intentPlan: plan
        )
    }
}

// MARK: - Local collection abstraction (adapter runt QueryDataFetcher)

/// Adapter-ytan du kopplar till din befintliga QueryDataFetcher.
/// Implementera detta genom att anropa QueryDataFetcher på det sätt ni gör idag,
/// men lås sources till en (samt sätt shouldCaptureLocation om source == .location).
protocol LocalQueryCollecting {
    func collect(
        source: QuerySource,
        timeRange: DateInterval?,
        intentPlan: BackendIntentPlanDTO,
        userQuery: UserQuery
    ) async throws -> LocalCollectedResult
}

/// Liten “stable DTO” för pipen.
/// Den här bör du kunna bygga från QueryDataFetcher-resultatet (items+entries),
/// men pipen behöver bara entries för UI.
struct LocalCollectedResult: Sendable, Equatable {
    let entries: [QueryResult.Entry]
}

// MARK: - Access gate abstraction (adapter runt QuerySourceAccess + SourceConnectionStore)

protocol QuerySourceAccessChecking {
    func isEnabled(_ source: QuerySource) -> Bool
    func isAllowed(_ source: QuerySource) -> Bool

    /// Valfri, men gör UX bättre.
    func deniedMessage(for source: QuerySource) -> String?
}

// MARK: - Helpers

private extension QueryPipeline {

    nonisolated static func mapDomainToSource(_ domain: BackendIntentDomain?) -> QuerySource? {
        switch domain {
        case .calendar: return .calendar
        case .reminders: return .reminders
        case .contacts: return .contacts
        case .photos: return .photos
        case .files: return .files
        case .location: return .location
        case .mail: return .mail
        case .notes, .memory:
            return .memory
        case .none:
            return nil
        }
    }

    nonisolated static func clarificationMessage(from plan: BackendIntentPlanDTO) -> String {
        let suggestions = plan.suggestions

        if suggestions.isEmpty {
            return "Jag behöver förtydligande – men jag vet inte vilken källa du menar."
        }
        if suggestions.count == 1 {
            return "Menar du \(localizedDomain(suggestions[0]))?"
        }

        let rendered = suggestions.prefix(3).map(localizedDomain).joined(separator: " eller ")
        return "Menar du \(rendered)?"
    }

    static func buildAnswer(
        plan: BackendIntentPlanDTO,
        collected: LocalCollectedResult,
        source: QuerySource,
        timeRange: DateInterval?
    ) -> String {
        let sourceLabel = localizedSource(source)
        let period = formattedPeriod(timeRange)
        let sortedEntries = sortedEntries(
            collected.entries,
            source: source,
            operation: plan.operation
        )
        let count = sortedEntries.count

        guard count > 0 else {
            if let period {
                return "Jag hittade inga poster i \(sourceLabel) för perioden \(period)."
            }
            return "Jag hittade inga poster i \(sourceLabel)."
        }

        let previewCount = min(maxDetailRows(for: source), count)
        let previewEntries = Array(sortedEntries.prefix(previewCount))
        var lines: [String] = []

        if let period {
            lines.append("Jag hittade \(count) poster i \(sourceLabel) för perioden \(period).")
        } else {
            lines.append("Jag hittade \(count) poster i \(sourceLabel).")
        }
        lines.append("Här är detaljerna:")

        for (index, entry) in previewEntries.enumerated() {
            lines.append(formattedEntryLine(entry, index: index + 1, source: source))
        }

        if count > previewCount {
            lines.append("Visar \(previewCount) av \(count) poster.")
        }

        return lines.joined(separator: "\n")
    }

    nonisolated static func localizedSource(_ source: QuerySource) -> String {
        switch source {
        case .calendar: return "kalendern"
        case .reminders: return "påminnelser"
        case .contacts: return "kontakter"
        case .photos: return "bilder"
        case .files: return "filer"
        case .location: return "plats"
        case .mail: return "mejl"
        default: return "data"
        }
    }

    nonisolated static func localizedDomain(_ domain: BackendIntentDomain) -> String {
        switch domain {
        case .calendar: return "kalender"
        case .reminders: return "påminnelser"
        case .mail: return "mejl"
        case .notes: return "anteckningar"
        case .files: return "filer"
        case .location: return "plats"
        case .photos: return "bilder"
        case .contacts: return "kontakter"
        case .memory: return "minne"
        }
    }

    static func formattedPeriod(_ range: DateInterval?) -> String? {
        guard let range else { return nil }
        var start = range.start
        var end = range.end
        if start > end { swap(&start, &end) }

        let formatter = DateService.shared.dateFormatter(dateStyle: .short, timeStyle: .short)
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    static func sortedEntries(
        _ entries: [QueryResult.Entry],
        source: QuerySource,
        operation: BackendIntentOperation
    ) -> [QueryResult.Entry] {
        let prefersDescendingDates = operation == .latest || source == .mail || source == .files || source == .photos

        if prefersDescendingDates {
            return entries.sorted { lhs, rhs in
                (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast)
            }
        }

        if source == .calendar || source == .reminders {
            return entries.sorted { lhs, rhs in
                (lhs.date ?? .distantFuture) < (rhs.date ?? .distantFuture)
            }
        }

        return entries.sorted { lhs, rhs in
            (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast)
        }
    }

    nonisolated static func maxDetailRows(for source: QuerySource) -> Int {
        switch source {
        case .calendar, .reminders:
            return 8
        case .mail:
            return 6
        default:
            return 7
        }
    }

    static func formattedEntryLine(
        _ entry: QueryResult.Entry,
        index: Int,
        source: QuerySource
    ) -> String {
        let cleanedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanedTitle.isEmpty ? "Utan titel" : cleanedTitle
        let timestamp = formattedEntryTimestamp(entry.date)
        let snippet = entrySnippet(entry, source: source)

        var line = "\(index). \(title)"
        if let timestamp, !timestamp.isEmpty {
            line += " (\(timestamp))"
        }
        if let snippet, !snippet.isEmpty {
            line += "\n   \(snippet)"
        }
        return line
    }

    static func formattedEntryTimestamp(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateService.shared.dateFormatter(dateStyle: .short, timeStyle: .short)
        return formatter.string(from: date)
    }

    nonisolated static func entrySnippet(_ entry: QueryResult.Entry, source: QuerySource) -> String? {
        let body = (entry.body ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !body.isEmpty {
            return clipped(body, maxLength: 140)
        }

        if source == .location, let lat = entry.latitude, let lon = entry.longitude {
            return "Koordinat: \(String(format: "%.5f", lat)), \(String(format: "%.5f", lon))"
        }

        return nil
    }

    nonisolated static func clipped(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let index = text.index(text.startIndex, offsetBy: maxLength)
        return text[..<index].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    // Use DateService for all date parsing/formatting to keep locale/timezone consistent
    // (DateService.shared.dateFormatter(...) is used in `buildAnswer`).
}
