import XCTest
@testable import Helper

@MainActor
final class BackendQueryPipelineTests: XCTestCase {

    func testBackendDataIntentResponseDecodesISO8601() throws {
        let json = """
        {
          "data_intent": {
            "domain": "calendar",
            "operation": "list",
            "timeframe": {
              "start": "2026-02-17T00:00:00Z",
              "end": "2026-02-17T23:59:59Z",
              "granularity": "day"
            },
            "filters": {
              "query": "standup"
            },
            "sort": {
              "field": "start_at",
              "direction": "asc"
            },
            "limit": 5,
            "fields": ["title"]
          }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try BackendQueryAPIService.decoder.decode(BackendDataIntentResponseDTO.self, from: data)

        XCTAssertEqual(decoded.dataIntent.domain, "calendar")
        XCTAssertEqual(decoded.dataIntent.operation, "list")
        XCTAssertEqual(decoded.dataIntent.timeframe?.granularity, "day")
        XCTAssertEqual(decoded.dataIntent.sort?.field, "start_at")
        XCTAssertEqual(decoded.dataIntent.sort?.direction, "asc")
        XCTAssertEqual(decoded.dataIntent.limit, 5)
        XCTAssertEqual(decoded.dataIntent.filters?["query"]?.value as? String, "standup")
    }

    func testBackendQueryRequestEncodesQueryQuestionAndLanguage() throws {
        let request = BackendQueryRequestDTO(
            query: "Vad händer idag?",
            question: "Vad händer idag?",
            language: "sv",
            sources: ["assistant_store"],
            days: 7,
            dataFilter: ["domain": AnyCodable("calendar")]
        )

        let data = try BackendQueryAPIService.encoder.encode(request)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(jsonObject["query"] as? String, "Vad händer idag?")
        XCTAssertEqual(jsonObject["question"] as? String, "Vad händer idag?")
        XCTAssertEqual(jsonObject["language"] as? String, "sv")
        XCTAssertEqual(jsonObject["days"] as? Int, 7)
    }

    func testNeedsClarificationSkipsCollectionAndIngest() async throws {
        let backend = MockBackendQueryService(
            response: BackendDataIntentResponseDTO(
                dataIntent: BackendDataIntentDTO(
                    domain: "unknown",
                    operation: "needs_clarification",
                    timeframe: nil,
                    filters: ["suggested_domains": AnyCodable(["calendar", "mail"])],
                    sort: nil,
                    limit: nil,
                    fields: nil
                )
            )
        )
        let fetcher = MockFetcher(result: emptyCollectedData())
        let ingest = MockIngestService()

        let result = try await makePipeline(fetcher: fetcher, ingest: ingest, backend: backend)
            .run(UserQuery(text: "vad händer nästa gång?"))

        XCTAssertEqual(fetcher.collectCallCount, 0)
        XCTAssertEqual(ingest.callCount, 0)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.answer, "Menar du kalender eller mejl?")
    }

    func testListOperationAppliesDomainTimeframeFiltersAndLimit() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = now.addingTimeInterval(-3_600)
        let end = now.addingTimeInterval(3_600)

        let backend = MockBackendQueryService(
            response: BackendDataIntentResponseDTO(
                dataIntent: BackendDataIntentDTO(
                    domain: "calendar",
                    operation: "list",
                    timeframe: BackendDataIntentTimeframeDTO(start: start, end: end, granularity: "day"),
                    filters: ["query": AnyCodable("plan")],
                    sort: BackendDataIntentSortDTO(field: "start_at", direction: "asc"),
                    limit: 1,
                    fields: nil
                )
            )
        )

        let matchingEarly = makeItem(
            id: UUID().uuidString,
            source: "calendar",
            type: .event,
            title: "Planeringsmöte",
            body: "Roadmap",
            date: now.addingTimeInterval(-600)
        )
        let matchingLater = makeItem(
            id: UUID().uuidString,
            source: "calendar",
            type: .event,
            title: "Planering sprint",
            body: "Detaljer",
            date: now.addingTimeInterval(900)
        )
        let nonMatchingDomain = makeItem(
            id: UUID().uuidString,
            source: "notes",
            type: .note,
            title: "Planering privat",
            body: "Ej kalender",
            date: now
        )

        let fetcher = MockFetcher(
            result: QueryCollectedData(
                timeRange: DateInterval(start: now.addingTimeInterval(-86_400), end: now),
                items: [matchingLater, nonMatchingDomain, matchingEarly],
                entries: [],
                missingAccess: [],
                checkpointSources: []
            )
        )

        let ingest = MockIngestService()
        let sourceStore = InMemorySourceConnectionStore()

        let result = try await makePipeline(
            fetcher: fetcher,
            ingest: ingest,
            backend: backend,
            sourceConnectionStore: sourceStore,
            nowProvider: { now }
        ).run(UserQuery(text: "visa plan"))

        XCTAssertEqual(fetcher.collectCallCount, 1)
        XCTAssertEqual(fetcher.lastOptions?.includeCalendar, true)
        XCTAssertEqual(fetcher.lastOptions?.includeReminders, false)
        XCTAssertEqual(fetcher.lastOptions?.shouldCaptureLocation, false)

        XCTAssertEqual(ingest.callCount, 1)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.title, "Planeringsmöte")
        XCTAssertTrue(result.answer?.contains("Här är 1 kalenderhändelser") == true)
    }

    func testCountOperationReturnsCountWithoutEntries() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let backend = MockBackendQueryService(
            response: BackendDataIntentResponseDTO(
                dataIntent: BackendDataIntentDTO(
                    domain: "notes",
                    operation: "count",
                    timeframe: nil,
                    filters: nil,
                    sort: nil,
                    limit: nil,
                    fields: nil
                )
            )
        )

        let fetcher = MockFetcher(
            result: QueryCollectedData(
                timeRange: DateInterval(start: now.addingTimeInterval(-86_400), end: now),
                items: [
                    makeItem(id: UUID().uuidString, source: "notes", type: .note, title: "A", body: "", date: now),
                    makeItem(id: UUID().uuidString, source: "notes", type: .note, title: "B", body: "", date: now.addingTimeInterval(-10))
                ],
                entries: [],
                missingAccess: [],
                checkpointSources: []
            )
        )

        let result = try await makePipeline(fetcher: fetcher, ingest: MockIngestService(), backend: backend)
            .run(UserQuery(text: "hur många anteckningar"))

        XCTAssertEqual(result.entries, [])
        XCTAssertEqual(result.answer, "Jag hittade 2 anteckningar.")
    }

    func testNextOperationReturnsNearestFutureItem() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let backend = MockBackendQueryService(
            response: BackendDataIntentResponseDTO(
                dataIntent: BackendDataIntentDTO(
                    domain: "reminders",
                    operation: "next",
                    timeframe: nil,
                    filters: nil,
                    sort: BackendDataIntentSortDTO(field: "due_at", direction: "asc"),
                    limit: nil,
                    fields: nil
                )
            )
        )

        let fetcher = MockFetcher(
            result: QueryCollectedData(
                timeRange: DateInterval(start: now.addingTimeInterval(-86_400), end: now.addingTimeInterval(86_400)),
                items: [
                    makeItem(id: UUID().uuidString, source: "reminders", type: .reminder, title: "Gammal", body: "", date: now.addingTimeInterval(-1_000)),
                    makeItem(id: UUID().uuidString, source: "reminders", type: .reminder, title: "Snart", body: "", date: now.addingTimeInterval(100)),
                    makeItem(id: UUID().uuidString, source: "reminders", type: .reminder, title: "Senare", body: "", date: now.addingTimeInterval(500))
                ],
                entries: [],
                missingAccess: [],
                checkpointSources: []
            )
        )

        let result = try await makePipeline(
            fetcher: fetcher,
            ingest: MockIngestService(),
            backend: backend,
            nowProvider: { now }
        ).run(UserQuery(text: "vad är nästa påminnelse"))

        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.title, "Snart")
        XCTAssertTrue(result.answer?.contains("Nästa påminnelse är") == true)
    }

    func testMissingAccessPrefixPrependedToAnswer() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let backend = MockBackendQueryService(
            response: BackendDataIntentResponseDTO(
                dataIntent: BackendDataIntentDTO(
                    domain: "calendar",
                    operation: "list",
                    timeframe: nil,
                    filters: nil,
                    sort: nil,
                    limit: 5,
                    fields: nil
                )
            )
        )

        let fetcher = MockFetcher(
            result: QueryCollectedData(
                timeRange: DateInterval(start: now.addingTimeInterval(-86_400), end: now),
                items: [
                    makeItem(id: UUID().uuidString, source: "calendar", type: .event, title: "Möte", body: "", date: now)
                ],
                entries: [],
                missingAccess: [.calendar, .files],
                checkpointSources: []
            )
        )

        let result = try await makePipeline(fetcher: fetcher, ingest: MockIngestService(), backend: backend)
            .run(UserQuery(text: "visa kalender"))

        XCTAssertTrue(result.answer?.contains("Obs: Kalenderåtkomst saknas") == true)
        XCTAssertTrue(result.answer?.contains("Obs: Ingen importerad fil-data hittades") == true)
        XCTAssertTrue(result.answer?.contains("Här är 1 kalenderhändelser") == true)
    }

    private func makePipeline(
        fetcher: MockFetcher,
        ingest: MockIngestService,
        backend: MockBackendQueryService,
        sourceConnectionStore: SourceConnectionStoring = InMemorySourceConnectionStore(),
        nowProvider: @escaping () -> Date = Date.init
    ) async throws -> QueryPipeline {
        QueryPipeline(
            access: MockAccess(),
            fetcher: fetcher,
            ingestService: ingest,
            backendQueryService: backend,
            checkpointStore: NoOpEtapp2IngestCheckpointStore(),
            sourceConnectionStore: sourceConnectionStore,
            memoryService: try MemoryService(inMemory: true),
            nowProvider: nowProvider
        )
    }

    private func emptyCollectedData() -> QueryCollectedData {
        QueryCollectedData(
            timeRange: DateInterval(start: .distantPast, end: .distantFuture),
            items: [],
            entries: [],
            missingAccess: [],
            checkpointSources: []
        )
    }

    private func makeItem(
        id: String,
        source: String,
        type: UnifiedItemTypeDTO,
        title: String,
        body: String,
        date: Date
    ) -> UnifiedItemDTO {
        UnifiedItemDTO(
            id: id,
            source: source,
            type: type,
            title: title,
            body: body,
            createdAt: date,
            updatedAt: date,
            startAt: date,
            endAt: nil,
            dueAt: date,
            status: [:]
        )
    }
}

private struct MockAccess: QuerySourceAccessing {
    func isAllowed(_ source: QuerySource) -> Bool { true }

    func assertAllowed(_ source: QuerySource) throws {
        if !isAllowed(source) {
            throw QueryPipelineError.sourceNotAllowed(source, deniedReason(for: source))
        }
    }

    func deniedReason(for source: QuerySource) -> String { "blocked" }
}

private final class MockFetcher: QueryDataFetching {
    private let result: QueryCollectedData

    private(set) var collectCallCount = 0
    private(set) var lastDays: Int?
    private(set) var lastOptions: QueryCollectionOptions?

    init(result: QueryCollectedData) {
        self.result = result
    }

    func collect(days: Int, access: QuerySourceAccessing) async throws -> QueryCollectedData {
        try await collect(days: days, access: access, options: .default)
    }

    func collect(days: Int, access: QuerySourceAccessing, options: QueryCollectionOptions) async throws -> QueryCollectedData {
        collectCallCount += 1
        lastDays = days
        lastOptions = options
        return result
    }
}

private final class MockIngestService: AssistantIngesting {
    private(set) var callCount = 0
    private(set) var lastItems: [UnifiedItemDTO] = []

    func ingest(items: [UnifiedItemDTO]) async throws {
        callCount += 1
        lastItems = items
    }
}

private final class MockBackendQueryService: BackendQuerying {
    private let response: BackendDataIntentResponseDTO

    init(response: BackendDataIntentResponseDTO) {
        self.response = response
    }

    func query(
        text: String,
        days: Int,
        sources: [String],
        dataFilter: [String: AnyCodable]?
    ) async throws -> BackendDataIntentResponseDTO {
        response
    }
}

private final class InMemorySourceConnectionStore: SourceConnectionStoring, @unchecked Sendable {
    private var enabledSources: Set<QuerySource> = []
    private var ocrSources: Set<QuerySource> = []
    private var importedFiles = false

    func isEnabled(_ source: QuerySource) -> Bool {
        enabledSources.contains(source)
    }

    func setEnabled(_ enabled: Bool, for source: QuerySource) {
        if enabled {
            enabledSources.insert(source)
        } else {
            enabledSources.remove(source)
        }
    }

    func isOCREnabled(for source: QuerySource) -> Bool {
        ocrSources.contains(source)
    }

    func setOCREnabled(_ enabled: Bool, for source: QuerySource) {
        if enabled {
            ocrSources.insert(source)
        } else {
            ocrSources.remove(source)
        }
    }

    func hasImportedFiles() -> Bool {
        importedFiles
    }

    func setHasImportedFiles(_ hasImportedFiles: Bool) {
        importedFiles = hasImportedFiles
    }
}
