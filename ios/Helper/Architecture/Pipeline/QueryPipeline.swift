import Foundation

struct QueryPipeline {

    let backendQueryService: BackendQuerying

    init(backendQueryService: BackendQuerying) {
        self.backendQueryService = backendQueryService
    }

    func run(_ query: UserQuery) async throws -> QueryResult {
        let response = try await backendQueryService.query(text: query.text)

        return QueryResult(
            timeRange: response.timeframe.map { DateInterval(start: $0.start, end: $0.end) },
            entries: response.entries.map(Self.toQueryResultEntry),
            answer: response.answer
        )
    }
}

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
}
