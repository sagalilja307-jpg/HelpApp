import Foundation

enum QueryPipelineError: Error, LocalizedError, Sendable {
    case sourceNotAllowed(QuerySource, String)

    var errorDescription: String? {
        switch self {
        case let .sourceNotAllowed(source, reason):
            return "Åtkomst nekad till \(source.rawValue): \(reason)"
        }
    }
}

private struct DomainEntry: Sendable, Equatable {
    let itemID: String
    let source: QuerySource
    let title: String
    let body: String?
    let date: Date?
}

private struct CollectedDomainData {
    let entries: [DomainEntry]
    let missingAccess: [QuerySource]
    let timeRange: DateInterval?
}

/// Backend-only intent orchestration:
/// 1) backend classifies query -> DataIntent
/// 2) iOS fetches local/source data for that intent
/// 3) iOS formats deterministic response locally
struct QueryPipeline {

    let access: QuerySourceAccessing
    let fetcher: QueryDataFetching
    let backendQueryService: BackendQuerying
    let sourceConnectionStore: SourceConnectionStoring
    let mailSyncService: MailSyncService
    let nowProvider: () -> Date

    init(
        access: QuerySourceAccessing,
        fetcher: QueryDataFetching,
        backendQueryService: BackendQuerying,
        sourceConnectionStore: SourceConnectionStoring = SourceConnectionStore.shared,
        mailSyncService: MailSyncService = .shared,
        nowProvider: @escaping () -> Date = DateService.shared.now
    ) {
        self.access = access
        self.fetcher = fetcher
        self.backendQueryService = backendQueryService
        self.sourceConnectionStore = sourceConnectionStore
        self.mailSyncService = mailSyncService
        self.nowProvider = nowProvider
    }
}

extension QueryPipeline {

    func run(_ query: UserQuery) async throws -> QueryResult {
        let days = Self.inferredDays(for: query.text)
        let intentResponse = try await backendQueryService.query(
            text: query.text,
            days: days,
            sources: ["assistant_store"],
            dataFilter: nil
        )
        let intent = intentResponse.dataIntent

        if intent.operation == "needs_clarification" {
            return QueryResult(
                timeRange: nil,
                entries: [],
                answer: Self.clarificationMessage(from: intent)
            )
        }

        let data = try await collectData(for: intent, days: days)
        let scoped = scopedEntries(for: intent, entries: data.entries)
        let operated = operate(on: scoped, intent: intent)
        let answer = composeAnswer(intent: intent, entries: operated, allEntries: scoped)

        let missingPrefix = Self.missingAccessPrefix(for: data.missingAccess)
        let finalAnswer: String
        if missingPrefix.isEmpty {
            finalAnswer = answer
        } else {
            finalAnswer = "\(missingPrefix)\n\n\(answer)"
        }

        let explicitTimeRange = intent.timeframe.map { DateInterval(start: $0.start, end: $0.end) }

        return QueryResult(
            timeRange: explicitTimeRange ?? data.timeRange,
            entries: operated.map(Self.toQueryResultEntry),
            answer: finalAnswer
        )
    }

    private func collectData(for intent: BackendDataIntentDTO, days: Int) async throws -> CollectedDomainData {
        if intent.domain == "mail" {
            let entries = try await fetchMailEntries(intent: intent)
            return CollectedDomainData(
                entries: entries,
                missingAccess: [],
                timeRange: dateRange(for: entries)
            )
        }

        let options = QueryCollectionOptions(
            shouldCaptureLocation: sourceConnectionStore.isEnabled(.location) && intent.domain == "location",
            includeCalendar: intent.domain == "calendar",
            includeReminders: intent.domain == "reminders"
        )

        let collected = try await fetcher.collect(days: days, access: access, options: options)
        let entries = collected.items.compactMap(Self.mapDomainEntry(from:))

        return CollectedDomainData(
            entries: entries,
            missingAccess: collected.missingAccess,
            timeRange: collected.timeRange
        )
    }

    private func scopedEntries(for intent: BackendDataIntentDTO, entries: [DomainEntry]) -> [DomainEntry] {
        let domainFiltered = entries.filter { Self.matches(domain: intent.domain, source: $0.source) }
        return applyTimeframe(domainFiltered, intent: intent)
    }

    private func applyTimeframe(_ entries: [DomainEntry], intent: BackendDataIntentDTO) -> [DomainEntry] {
        guard let timeframe = intent.timeframe else { return entries }
        return entries.filter { entry in
            guard let date = entry.date else { return false }
            return date >= timeframe.start && date <= timeframe.end
        }
    }

    private func operate(on entries: [DomainEntry], intent: BackendDataIntentDTO) -> [DomainEntry] {
        let filtered = applyFilters(entries, intent: intent)
        switch intent.operation {
        case "count", "needs_clarification":
            return []
        case "next":
            let sorted = sort(filtered, intent: intent, forcedDirection: "asc")
            if let nextItem = sorted.first(where: { ($0.date ?? .distantFuture) >= nowProvider() }) {
                return [nextItem]
            }
            return sorted.first.map { [$0] } ?? []
        case "details":
            let sorted = sort(filtered, intent: intent, forcedDirection: nil)
            return sorted.first.map { [$0] } ?? []
        case "list", "search":
            let sorted = sort(filtered, intent: intent, forcedDirection: nil)
            let limit = max(1, intent.limit ?? 20)
            return Array(sorted.prefix(limit))
        default:
            return []
        }
    }

    private func applyFilters(_ entries: [DomainEntry], intent: BackendDataIntentDTO) -> [DomainEntry] {
        var out = entries

        if let idFilter = intent.filters?["id"]?.value as? String {
            out = out.filter { $0.itemID == idFilter }
        }

        if let rawQuery = intent.filters?["query"]?.value as? String {
            let needle = rawQuery.lowercased()
            out = out.filter { entry in
                entry.title.lowercased().contains(needle) ||
                (entry.body?.lowercased().contains(needle) ?? false)
            }
        }

        return out
    }

    private func sort(_ entries: [DomainEntry], intent: BackendDataIntentDTO, forcedDirection: String?) -> [DomainEntry] {
        let field = intent.sort?.field.lowercased() ?? "date"
        let direction = (forcedDirection ?? intent.sort?.direction ?? "desc").lowercased()
        let ascending = direction == "asc"

        let sorted: [DomainEntry]
        if field.contains("date") || field.contains("start") || field.contains("due") || field.contains("observed") {
            sorted = entries.sorted { lhs, rhs in
                let left = lhs.date ?? .distantPast
                let right = rhs.date ?? .distantPast
                if left == right {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return ascending ? left < right : left > right
            }
        } else {
            sorted = entries.sorted { lhs, rhs in
                let result = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }
        }
        return sorted
    }

    private func composeAnswer(intent: BackendDataIntentDTO, entries: [DomainEntry], allEntries: [DomainEntry]) -> String {
        let domainLabel = Self.domainLabel(intent.domain, plural: true)
        let singularLabel = Self.domainLabel(intent.domain, plural: false)

        switch intent.operation {
        case "count":
            return "Jag hittade \(allEntries.count) \(domainLabel)."
        case "next":
            guard let nextItem = entries.first else {
                return "Jag hittar ingen kommande \(singularLabel)."
            }
            return "Nästa \(singularLabel) är \(Self.formatEntry(nextItem))."
        case "details":
            guard let item = entries.first else {
                return "Jag hittar inga detaljer för den begäran."
            }
            if let body = item.body, !body.isEmpty {
                return "\(item.title)\n\(body)"
            }
            return item.title
        case "search":
            if entries.isEmpty {
                return "Jag hittade inga sökresultat."
            }
            return Self.listSummary(prefix: "Sökresultat", entries: entries)
        case "list":
            if entries.isEmpty {
                return "Jag hittar ingen data att svara på ännu."
            }
            return Self.listSummary(prefix: "Här är \(entries.count) \(domainLabel)", entries: entries)
        default:
            return "Jag behöver förtydligande för att fortsätta."
        }
    }

    private func fetchMailEntries(intent: BackendDataIntentDTO) async throws -> [DomainEntry] {
        let statusFilter = (intent.filters?["status"]?.value as? String)?.lowercased()
        let limit = max(1, intent.limit ?? 20)
        let mails: [Mail]
        if statusFilter == "unread" || statusFilter == "unanswered" {
            mails = try await mailSyncService.fetchUnansweredMails(limit: max(limit, 50))
        } else {
            let days = intent.timeframe.map { max(1, Int($0.end.timeIntervalSince($0.start) / 86400)) } ?? 30
            mails = try await mailSyncService.fetchRecentMails(days: max(days, 1), limit: max(limit, 50))
        }

        return mails.map { mail in
            DomainEntry(
                itemID: mail.id.uuidString,
                source: .rawEvents,
                title: mail.subject,
                body: mail.sender,
                date: mail.date
            )
        }
    }

    private func dateRange(for entries: [DomainEntry]) -> DateInterval? {
        let dates = entries.compactMap(\.date)
        guard let minDate = dates.min(), let maxDate = dates.max() else { return nil }
        return DateInterval(start: minDate, end: maxDate)
    }

    private static func mapDomainEntry(from item: UnifiedItemDTO) -> DomainEntry? {
        let source = mapSource(item.source)
        let date = item.startAt ?? item.dueAt ?? item.updatedAt ?? item.createdAt
        let body = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return DomainEntry(
            itemID: item.id,
            source: source,
            title: item.title,
            body: body.isEmpty ? nil : body,
            date: date
        )
    }

    private static func toQueryResultEntry(_ entry: DomainEntry) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(uuidString: entry.itemID) ?? UUID(),
            source: entry.source,
            title: entry.title,
            body: entry.body,
            date: entry.date
        )
    }

    private static func matches(domain: String, source: QuerySource) -> Bool {
        switch domain {
        case "calendar":
            return source == .calendar
        case "reminders":
            return source == .reminders
        case "contacts":
            return source == .contacts
        case "photos":
            return source == .photos
        case "files":
            return source == .files
        case "location":
            return source == .location
        case "notes":
            return source == .memory
        case "mail":
            return source == .rawEvents
        default:
            return false
        }
    }

    private static func mapSource(_ source: String) -> QuerySource {
        switch source.lowercased() {
        case "calendar":
            return .calendar
        case "reminders", "tasks":
            return .reminders
        case "notes":
            return .memory
        case "contacts":
            return .contacts
        case "photos":
            return .photos
        case "files":
            return .files
        case "location", "locations":
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
            messages.append("Obs: Påminnelseåtkomst saknas")
        }
        if missing.contains(.contacts) {
            messages.append("Obs: Kontaktåtkomst saknas")
        }
        if missing.contains(.photos) {
            messages.append("Obs: Bildåtkomst saknas")
        }
        if missing.contains(.files) {
            messages.append("Obs: Ingen importerad fil-data hittades")
        }
        if missing.contains(.location) {
            messages.append("Obs: Platsåtkomst saknas")
        }

        return messages.joined(separator: "\n")
    }

    private static func inferredDays(for text: String) -> Int {
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

        return 90
    }

    private static func clarificationMessage(from intent: BackendDataIntentDTO) -> String {
        guard
            let rawDomains = intent.filters?["suggested_domains"]?.value as? [Any]
        else {
            return "Menar du kalender eller mejl?"
        }
        let domains = rawDomains.compactMap { $0 as? String }
        if domains.isEmpty {
            return "Menar du kalender eller mejl?"
        }
        if domains.count == 1 {
            return "Menar du \(localizedDomain(domains[0]))?"
        }
        let rendered = domains.prefix(3).map(localizedDomain).joined(separator: " eller ")
        return "Menar du \(rendered)?"
    }

    private static func localizedDomain(_ domain: String) -> String {
        switch domain {
        case "calendar":
            return "kalender"
        case "reminders":
            return "påminnelser"
        case "mail":
            return "mejl"
        case "contacts":
            return "kontakter"
        case "photos":
            return "bilder"
        case "files":
            return "filer"
        case "location":
            return "plats"
        case "notes":
            return "anteckningar"
        default:
            return domain
        }
    }

    private static func domainLabel(_ domain: String, plural: Bool) -> String {
        switch (domain, plural) {
        case ("calendar", true):
            return "kalenderhändelser"
        case ("calendar", false):
            return "kalenderhändelse"
        case ("reminders", true):
            return "påminnelser"
        case ("reminders", false):
            return "påminnelse"
        case ("mail", true):
            return "mejl"
        case ("mail", false):
            return "mejl"
        case ("contacts", true):
            return "kontakter"
        case ("contacts", false):
            return "kontakt"
        case ("photos", true):
            return "bilder"
        case ("photos", false):
            return "bild"
        case ("files", true):
            return "filer"
        case ("files", false):
            return "fil"
        case ("location", true):
            return "platser"
        case ("location", false):
            return "plats"
        case ("notes", true):
            return "anteckningar"
        case ("notes", false):
            return "anteckning"
        default:
            return plural ? "poster" : "post"
        }
    }

    private static func listSummary(prefix: String, entries: [DomainEntry]) -> String {
        let rows = entries.map { "- \(formatEntry($0))" }.joined(separator: "\n")
        return "\(prefix):\n\(rows)"
    }

    private static func formatEntry(_ entry: DomainEntry) -> String {
        if let date = entry.date {
            return "\(entry.title) (\(dateFormatter.string(from: date)))"
        }
        return entry.title
    }

    private static let dateFormatter: DateFormatter = {
        DateService.shared.dateFormatter(
            dateStyle: .short,
            timeStyle: .short
        )
    }()
}
