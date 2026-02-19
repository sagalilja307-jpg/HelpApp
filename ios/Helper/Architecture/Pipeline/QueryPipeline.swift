import Foundation

/// Transport-only pipeline:
/// - iOS skickar bara query
/// - backend returnerar intent_plan (+ ev. answer/entries senare)
struct QueryPipeline {

    let backendQueryService: BackendQuerying

    init(backendQueryService: BackendQuerying) {
        self.backendQueryService = backendQueryService
    }

    func run(_ query: UserQuery) async throws -> QueryResult {
        let response = try await backendQueryService.query(text: query.text)
        let plan = response.intentPlan

        // 1) Clarification flow
        if plan.needsClarification {
            let suggestions = plan.suggestions
            let message: String
            if suggestions.isEmpty {
                message = "Jag behöver förtydligande – men jag vet inte vilken källa du menar."
            } else if suggestions.count == 1 {
                message = "Menar du \(Self.localizedDomain(suggestions[0]))?"
            } else {
                let rendered = suggestions.prefix(3).map(Self.localizedDomain).joined(separator: " eller ")
                message = "Menar du \(rendered)?"
            }

            return QueryResult(
                timeRange: nil,
                entries: [],
                answer: message
            )
        }

        // 2) Normal flow
        let timeRange: DateInterval? = plan.timeframe.map { DateInterval(start: $0.start, end: $0.end) }

        let entries: [QueryResult.Entry] = (response.entries ?? []).map(Self.toQueryResultEntry)

        // Prefer backend answer if provided, otherwise fallback
        let answer = response.answer ?? Self.fallbackAnswer(from: plan)

        return QueryResult(
            timeRange: timeRange,
            entries: entries,
            answer: answer
        )
    }
}

// MARK: - Mapping + UX helpers

private extension QueryPipeline {

    static func toQueryResultEntry(_ dto: BackendQueryEntryDTO) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(uuidString: dto.id) ?? UUID(),
            source: mapSource(dto.source),
            title: dto.title,
            body: dto.body,
            date: dto.date
        )
    }

    static func mapSource(_ source: String) -> QuerySource {
        switch source.lowercased() {
        case "calendar": return .calendar
        case "reminders", "tasks": return .reminders
        case "notes": return .memory
        case "contacts": return .contacts
        case "photos": return .photos
        case "files": return .files
        case "location", "locations": return .location
        case "mail", "email": return .rawEvents
        default: return .rawEvents
        }
    }

    static func localizedDomain(_ domain: String) -> String {
        switch domain {
        case "calendar": return "kalender"
        case "reminders": return "påminnelser"
        case "mail": return "mejl"
        case "notes": return "anteckningar"
        case "files": return "filer"
        case "location": return "plats"
        case "photos": return "bilder"
        case "contacts": return "kontakter"
        default: return domain
        }
    }

    static func fallbackAnswer(from plan: BackendIntentPlanDTO) -> String {
        // Minimal, deterministic fallback tills backend skickar "answer".
        let domain = plan.domain.map(localizedDomain) ?? "okänd källa"
        let op = plan.operation

        if let tf = plan.timeframe {
            let start = dateFormatter.string(from: tf.start)
            let end = dateFormatter.string(from: tf.end)
            return "Plan: \(op) i \(domain) (\(start) – \(end))."
        } else {
            return "Plan: \(op) i \(domain)."
        }
    }

    static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        df.timeZone = TimeZone.current
        return df
    }()
}
