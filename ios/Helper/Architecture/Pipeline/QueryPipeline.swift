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
            return QueryResult(timeRange: nil, entries: [], answer: "Förlåt, kunde inte kontakta servern: \(error.localizedDescription)")
        }
        let plan = response.intentPlan

        // 1) Clarification flow (källa)
        if plan.needsClarification || plan.domain == nil {
            return QueryResult(
                timeRange: nil,
                entries: [],
                answer: Self.clarificationMessage(from: plan)
            )
        }

        // 2) Domain -> QuerySource (MVP: alla utom memory/mail)
        guard let source = Self.mapDomainToSource(plan.domain) else {
            let domain = plan.domain?.rawValue ?? "okänd"
            return QueryResult(
                timeRange: nil,
                entries: [],
                answer: "Jag kan inte hämta data för \"\(domain)\" än."
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
                answer: "Källan \(Self.localizedSource(source)) är inte aktiverad."
            )
        }
        if !accessGate.isAllowed(source) {
            return QueryResult(
                timeRange: timeRange,
                entries: [],
                answer: accessGate.deniedMessage(for: source) ?? "Jag har inte access till \(Self.localizedSource(source))."
            )
        }

        // 5) Local fetch (en källa i taget)
        let collected: LocalCollectedResult
        do {
            collected = try await localCollector.collect(
                source: source,
                timeRange: timeRange,
                userQuery: query
            )
        } catch {
            return QueryResult(
                timeRange: timeRange,
                entries: [],
                answer: "Kunde inte hämta data lokalt: \(error.localizedDescription)"
            )
        }

        // 6) Operation (MVP: backend skickar count; vi bygger deterministiskt svar lokalt)
        let answer = Self.buildAnswer(plan: plan, collected: collected, source: source, timeRange: timeRange)

        return QueryResult(
            timeRange: timeRange,
            entries: collected.entries,
            answer: answer
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
        case .mail, .notes, .memory, .none:
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
        // MVP: bara count (ni kan bygga ut senare för list/search)
        let count = collected.entries.count
        let src = localizedSource(source)

        if let tf = timeRange {
            var start = tf.start
            var end = tf.end
            if start > end { swap(&start, &end) }

            let df = DateService.shared.dateFormatter(dateStyle: .short, timeStyle: .short)
            let startS = df.string(from: start)
            let endS = df.string(from: end)
            // "halvöppet" intervall i backend men vi renderar bara läsbart.
            return "\(count) saker i \(src) (\(startS) – \(endS))."
        } else {
            return "\(count) saker i \(src)."
        }
    }

    nonisolated static func localizedSource(_ source: QuerySource) -> String {
        switch source {
        case .calendar: return "kalendern"
        case .reminders: return "påminnelser"
        case .contacts: return "kontakter"
        case .photos: return "bilder"
        case .files: return "filer"
        case .location: return "plats"
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

    // Use DateService for all date parsing/formatting to keep locale/timezone consistent
    // (DateService.shared.dateFormatter(...) is used in `buildAnswer`).
}
