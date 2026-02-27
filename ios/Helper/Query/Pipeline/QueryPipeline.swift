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

        // 3) Resolve time range från backend-planen (även när start/end saknas).
        let timeRange = Self.resolvedTimeRange(
            timeScope: plan.timeScope,
            source: source
        )

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

        // 6) Applicera backend-filter lokalt innan svar byggs.
        let filteredEntries = Self.filteredEntries(
            collected.entries,
            plan: plan,
            source: source
        )
        let filteredCollected = LocalCollectedResult(entries: filteredEntries)

        // 7) Operation (MVP: backend skickar count; vi bygger deterministiskt svar lokalt)
        let answer = Self.buildAnswer(
            plan: plan,
            collected: filteredCollected,
            source: source,
            timeRange: timeRange
        )

        return QueryResult(
            timeRange: timeRange,
            entries: filteredEntries,
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

    static func resolvedTimeRange(
        timeScope: BackendTimeScopeDTO,
        source: QuerySource
    ) -> DateInterval? {
        if let start = timeScope.start, let end = timeScope.end {
            return normalizedInterval(start: start, end: end)
        }

        if let rangeFromValue = rangeFromTimeScopeValue(timeScope) {
            return rangeFromValue
        }

        if timeScope.type == .all {
            return defaultRangeForAllScope(source: source)
        }

        return nil
    }

    static func rangeFromTimeScopeValue(_ timeScope: BackendTimeScopeDTO) -> DateInterval? {
        guard let rawValue = timeScope.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        switch timeScope.type {
        case .all:
            return nil
        case .absolute:
            if let range = parseAbsoluteRange(rawValue) {
                return range
            }
            guard let date = parseDate(rawValue) else { return nil }
            return dayRange(containing: date)
        case .relative:
            return relativeRange(from: rawValue)
        }
    }

    static func filteredEntries(
        _ entries: [QueryResult.Entry],
        plan: BackendIntentPlanDTO,
        source: QuerySource
    ) -> [QueryResult.Entry] {
        guard !entries.isEmpty else { return entries }

        let senderTerms = source == .mail
            ? filterTerms(
                in: plan.filters,
                keyHints: ["from", "sender", "participants", "participant", "domain", "company", "brand", "mailbox", "email", "org", "organization", "source_account"],
                includeQueryHints: true
            )
            : []

        let entityTerms = filterTerms(
            in: plan.filters,
            keyHints: ["name", "person", "contact", "participant", "attendee", "who", "query", "keyword", "subject", "title", "text_contains", "location", "tags", "priority"],
            includeQueryHints: true
        )

        var result = entries

        if !senderTerms.isEmpty {
            result = result.filter { entry in
                matches(entry: entry, terms: senderTerms)
            }
        }

        // Avoid double-filtering on same terms for mail.
        let effectiveEntityTerms: [String]
        if source == .mail {
            let senderSet = Set(senderTerms.map(normalizedText))
            effectiveEntityTerms = entityTerms.filter { !senderSet.contains(normalizedText($0)) }
        } else {
            effectiveEntityTerms = entityTerms
        }

        if !effectiveEntityTerms.isEmpty {
            result = result.filter { entry in
                matches(entry: entry, terms: effectiveEntityTerms)
            }
        }

        return result
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

    static func normalizedInterval(start: Date, end: Date) -> DateInterval {
        if start <= end {
            return DateInterval(start: start, end: end)
        }
        return DateInterval(start: end, end: start)
    }

    static func defaultRangeForAllScope(source: QuerySource) -> DateInterval? {
        let now = DateService.shared.now()
        let calendar = Calendar.current

        switch source {
        case .mail:
            // Mail hämtar "senaste" via Gmail maxResults när scope är all.
            return nil
        case .calendar, .reminders:
            let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            let end = calendar.date(byAdding: .year, value: 2, to: now) ?? now
            return normalizedInterval(start: start, end: end)
        case .contacts:
            let start = calendar.date(byAdding: .year, value: -20, to: now) ?? now
            let end = calendar.date(byAdding: .year, value: 1, to: now) ?? now
            return normalizedInterval(start: start, end: end)
        default:
            let start = calendar.date(byAdding: .year, value: -2, to: now) ?? now
            let end = calendar.date(byAdding: .year, value: 1, to: now) ?? now
            return normalizedInterval(start: start, end: end)
        }
    }

    static func parseAbsoluteRange(_ rawValue: String) -> DateInterval? {
        let separators = ["..", "/", "|"]
        for separator in separators {
            let parts = rawValue.components(separatedBy: separator)
            guard parts.count == 2 else { continue }
            guard let start = parseDate(parts[0]), let end = parseDate(parts[1]) else { continue }
            return normalizedInterval(start: start, end: end)
        }

        if rawValue.contains(" to ") {
            let parts = rawValue.components(separatedBy: " to ")
            if parts.count == 2,
               let start = parseDate(parts[0]),
               let end = parseDate(parts[1]) {
                return normalizedInterval(start: start, end: end)
            }
        }

        return nil
    }

    static func relativeRange(from rawValue: String) -> DateInterval? {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        let calendar = Calendar.current
        let now = DateService.shared.now()
        let startOfToday = calendar.startOfDay(for: now)

        switch value {
        case "today", "today_morning", "today_day", "today_afternoon", "today_evening":
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return nil }
            return normalizedInterval(start: startOfToday, end: tomorrow)

        case "yesterday":
            guard
                let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)
            else { return nil }
            return normalizedInterval(start: yesterday, end: startOfToday)

        case "tomorrow":
            guard
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
                let dayAfter = calendar.date(byAdding: .day, value: 2, to: startOfToday)
            else { return nil }
            return normalizedInterval(start: tomorrow, end: dayAfter)

        case "this_week", "current_week", "week":
            return weekRange(offsetWeeks: 0, from: now)
        case "next_week", "upcoming_week":
            return weekRange(offsetWeeks: 1, from: now)
        case "last_week", "previous_week":
            return weekRange(offsetWeeks: -1, from: now)

        case "this_month", "current_month":
            return monthRange(offsetMonths: 0, from: now)
        case "next_month":
            return monthRange(offsetMonths: 1, from: now)
        case "last_month", "previous_month":
            return monthRange(offsetMonths: -1, from: now)

        case "this_year", "current_year":
            return yearRange(offsetYears: 0, from: now)
        case "next_year":
            return yearRange(offsetYears: 1, from: now)
        case "last_year", "previous_year":
            return yearRange(offsetYears: -1, from: now)

        default:
            break
        }

        if let range = rollingWindowRange(from: value, now: now) {
            return range
        }

        return nil
    }

    static func rollingWindowRange(from token: String, now: Date) -> DateInterval? {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        let nextWindow = token.split(separator: "_").map(String.init)
        if nextWindow.count == 2, nextWindow[0] == "next",
           let (amount, component) = parseDurationToken(nextWindow[1]) {
            guard let end = calendar.date(byAdding: component, value: amount, to: startOfToday) else { return nil }
            return normalizedInterval(start: startOfToday, end: end)
        }

        if token == "7d" || token == "30d" || token == "3m" || token == "1y" {
            guard let (amount, component) = parseDurationToken(token),
                  let start = calendar.date(byAdding: component, value: -amount, to: now),
                  let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
                return nil
            }
            return normalizedInterval(start: start, end: end)
        }

        if let (amount, component) = parseDurationToken(token) {
            guard let start = calendar.date(byAdding: component, value: -amount, to: now),
                  let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
                return nil
            }
            return normalizedInterval(start: start, end: end)
        }

        return nil
    }

    static func parseDurationToken(_ token: String) -> (Int, Calendar.Component)? {
        let lower = token.lowercased()
        guard let unit = lower.last else { return nil }

        let numericPart = String(lower.dropLast())
        guard let amount = Int(numericPart), amount > 0 else { return nil }

        let component: Calendar.Component
        switch unit {
        case "d":
            component = .day
        case "m":
            component = .month
        case "y":
            component = .year
        default:
            return nil
        }

        return (amount, component)
    }

    static func weekRange(offsetWeeks: Int, from date: Date) -> DateInterval? {
        let calendar = Calendar.current
        guard
            let baseWeek = calendar.dateInterval(of: .weekOfYear, for: date),
            let start = calendar.date(byAdding: .weekOfYear, value: offsetWeeks, to: baseWeek.start),
            let end = calendar.date(byAdding: .day, value: 7, to: start)
        else { return nil }
        return normalizedInterval(start: start, end: end)
    }

    static func monthRange(offsetMonths: Int, from date: Date) -> DateInterval? {
        let calendar = Calendar.current
        guard
            let currentMonth = calendar.dateInterval(of: .month, for: date),
            let start = calendar.date(byAdding: .month, value: offsetMonths, to: currentMonth.start),
            let end = calendar.date(byAdding: .month, value: 1, to: start)
        else { return nil }
        return normalizedInterval(start: start, end: end)
    }

    static func yearRange(offsetYears: Int, from date: Date) -> DateInterval? {
        let calendar = Calendar.current
        guard
            let currentYear = calendar.dateInterval(of: .year, for: date),
            let start = calendar.date(byAdding: .year, value: offsetYears, to: currentYear.start),
            let end = calendar.date(byAdding: .year, value: 1, to: start)
        else { return nil }
        return normalizedInterval(start: start, end: end)
    }

    static func dayRange(containing date: Date) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return normalizedInterval(start: start, end: end)
    }

    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let parsedISO = DateService.shared.parseISO8601(trimmed) {
            return parsedISO
        }

        let formatterVariants = [
            DateService.shared.dateFormatter(dateFormat: "yyyy-MM-dd"),
            DateService.shared.dateFormatter(dateFormat: "yyyy/MM/dd"),
            DateService.shared.dateFormatter(dateFormat: "dd/MM/yyyy")
        ]

        for formatter in formatterVariants {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }

    static func filterTerms(
        in filters: [String: AnyCodable],
        keyHints: [String],
        includeQueryHints: Bool
    ) -> [String] {
        let hintSet = Set(keyHints.map { $0.lowercased() })
        var collected: [String] = []

        for (key, value) in filters {
            collectFilterTerms(
                value: value.value,
                key: key.lowercased(),
                keyHints: hintSet,
                includeQueryHints: includeQueryHints,
                output: &collected
            )
        }

        var seen: Set<String> = []
        return collected.filter { term in
            let normalized = normalizedText(term)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
    }

    static func collectFilterTerms(
        value: Any,
        key: String,
        keyHints: Set<String>,
        includeQueryHints: Bool,
        output: inout [String]
    ) {
        switch value {
        case let text as String:
            let shouldUseDirect = keyHints.contains(where: { key.contains($0) })
            if shouldUseDirect {
                output.append(contentsOf: splitSearchTerms(from: text))
                return
            }

            if includeQueryHints && key == "query" {
                output.append(contentsOf: entityTerms(fromQuery: text))
            }

        case let nested as [String: Any]:
            for (nestedKey, nestedValue) in nested {
                collectFilterTerms(
                    value: nestedValue,
                    key: nestedKey.lowercased(),
                    keyHints: keyHints,
                    includeQueryHints: includeQueryHints,
                    output: &output
                )
            }

        case let array as [Any]:
            for item in array {
                collectFilterTerms(
                    value: item,
                    key: key,
                    keyHints: keyHints,
                    includeQueryHints: includeQueryHints,
                    output: &output
                )
            }

        case let nestedAnyCodables as [String: AnyCodable]:
            for (nestedKey, nestedValue) in nestedAnyCodables {
                collectFilterTerms(
                    value: nestedValue.value,
                    key: nestedKey.lowercased(),
                    keyHints: keyHints,
                    includeQueryHints: includeQueryHints,
                    output: &output
                )
            }

        case let anyCodableArray as [AnyCodable]:
            for nestedValue in anyCodableArray {
                collectFilterTerms(
                    value: nestedValue.value,
                    key: key,
                    keyHints: keyHints,
                    includeQueryHints: includeQueryHints,
                    output: &output
                )
            }

        default:
            return
        }
    }

    static func splitSearchTerms(from raw: String) -> [String] {
        raw.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func entityTerms(fromQuery query: String) -> [String] {
        let normalized = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let tokens = normalized
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)

        let stopwords: Set<String> = [
            "vad", "har", "jag", "for", "fran", "från", "med", "mina", "mitt", "vilken",
            "vilket", "dag", "datum", "gör", "gor", "nasta", "nästa", "vecka", "manad", "månad",
            "ar", "år", "idag", "imorgon", "igar", "igår", "today", "tomorrow", "yesterday",
            "week", "month", "year", "mail", "mejl", "email", "from"
        ]

        let filtered = tokens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                guard token.count >= 2 else { return false }
                return !stopwords.contains(token)
            }

        if filtered.count <= 3 {
            return filtered
        }
        return []
    }

    static func matches(entry: QueryResult.Entry, terms: [String]) -> Bool {
        let haystack = normalizedText([entry.title, entry.body ?? ""].joined(separator: " "))
        guard !haystack.isEmpty else { return false }

        return terms.allSatisfy { rawTerm in
            let term = normalizedText(rawTerm)
            guard !term.isEmpty else { return true }
            return haystack.contains(term)
        }
    }

    nonisolated static func normalizedText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Use DateService for all date parsing/formatting to keep locale/timezone consistent
    // (DateService.shared.dateFormatter(...) is used in `buildAnswer`).
}
