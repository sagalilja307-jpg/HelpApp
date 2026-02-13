import XCTest
@testable import Helper

@MainActor
final class BackendQueryPipelineTests: XCTestCase {

    func testPipelineRunsCollectIngestQueryInOrder() async throws {
        let recorder = CallRecorder()

        let interpreter = MockInterpreter(result: QueryInterpretation(
            intent: .overview,
            requiredSources: [.memory],
            timeRange: nil,
            confidence: 0.9
        ))
        let access = MockAccess()
        let fetcher = MockFetcher(
            recorder: recorder,
            result: QueryCollectedData(
                timeRange: DateInterval(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200)),
                items: [
                    UnifiedItemDTO(
                        id: "memory:item-1",
                        source: "notes",
                        type: .note,
                        title: "Packlista",
                        body: "Pass",
                        createdAt: Date(timeIntervalSince1970: 100),
                        updatedAt: Date(timeIntervalSince1970: 100),
                        startAt: nil,
                        endAt: nil,
                        dueAt: nil,
                        status: [:]
                    )
                ],
                entries: [],
                missingAccess: []
            )
        )

        let ingest = MockIngestService(recorder: recorder)
        let backend = MockBackendQueryService(
            recorder: recorder,
            response: BackendLLMResponseDTO(
                content: "Du har en planerad aktivitet idag.",
                confidence: nil,
                sourceDocuments: nil,
                evidenceItems: nil,
                usedSources: ["notes"],
                timeRange: nil
            )
        )

        let pipeline = QueryPipeline(
            interpreter: interpreter,
            access: access,
            fetcher: fetcher,
            ingestService: ingest,
            backendQueryService: backend
        )

        let result = try await pipeline.run(UserQuery(text: "Vad hander idag?", source: .userTyped))

        XCTAssertEqual(recorder.calls, ["collect", "ingest", "query"])
        XCTAssertEqual(result.answer, "Du har en planerad aktivitet idag.")
        XCTAssertEqual(backend.lastDays, 7)
        XCTAssertEqual(backend.lastSources, ["assistant_store"])
    }

    func testPipelineStopsWhenIngestFails() async {
        let recorder = CallRecorder()
        let pipeline = QueryPipeline(
            interpreter: MockInterpreter(result: QueryInterpretation(
                intent: .summary,
                requiredSources: [.memory],
                timeRange: nil,
                confidence: nil
            )),
            access: MockAccess(),
            fetcher: MockFetcher(
                recorder: recorder,
                result: QueryCollectedData(
                    timeRange: DateInterval(start: Date(), end: Date()),
                    items: [
                        UnifiedItemDTO(
                            id: "memory:item-2",
                            source: "notes",
                            type: .note,
                            title: "Anteckning",
                            body: "Body",
                            createdAt: Date(),
                            updatedAt: Date(),
                            startAt: nil,
                            endAt: nil,
                            dueAt: nil,
                            status: [:]
                        )
                    ],
                    entries: [],
                    missingAccess: []
                )
            ),
            ingestService: MockIngestService(recorder: recorder, error: MockPipelineError.failedIngest),
            backendQueryService: MockBackendQueryService(
                recorder: recorder,
                response: BackendLLMResponseDTO(
                    content: "Should not be called",
                    confidence: nil,
                    sourceDocuments: nil,
                    evidenceItems: nil,
                    usedSources: nil,
                    timeRange: nil
                )
            )
        )

        do {
            _ = try await pipeline.run(UserQuery(text: "Sammanfatta", source: .userTyped))
            XCTFail("Expected ingest failure")
        } catch {
            XCTAssertEqual(recorder.calls, ["collect", "ingest"])
        }
    }

    func testMissingPermissionsAddsAnswerPrefix() async throws {
        let pipeline = QueryPipeline(
            interpreter: MockInterpreter(result: QueryInterpretation(
                intent: .summary,
                requiredSources: [.memory],
                timeRange: nil,
                confidence: nil
            )),
            access: MockAccess(),
            fetcher: MockFetcher(
                recorder: CallRecorder(),
                result: QueryCollectedData(
                    timeRange: DateInterval(start: Date(), end: Date()),
                    items: [
                        UnifiedItemDTO(
                            id: "memory:item-3",
                            source: "notes",
                            type: .note,
                            title: "Anteckning",
                            body: "Body",
                            createdAt: Date(),
                            updatedAt: Date(),
                            startAt: nil,
                            endAt: nil,
                            dueAt: nil,
                            status: [:]
                        )
                    ],
                    entries: [],
                    missingAccess: [.calendar, .reminders, .contacts, .photos, .files]
                )
            ),
            ingestService: MockIngestService(recorder: CallRecorder()),
            backendQueryService: MockBackendQueryService(
                recorder: CallRecorder(),
                response: BackendLLMResponseDTO(
                    content: "Har ar din sammanfattning.",
                    confidence: nil,
                    sourceDocuments: nil,
                    evidenceItems: nil,
                    usedSources: nil,
                    timeRange: nil
                )
            )
        )

        let result = try await pipeline.run(UserQuery(text: "Hur ser mina planer ut?", source: .userTyped))

        XCTAssertTrue(result.answer?.contains("Obs: Kalenderatkomst saknas") == true)
        XCTAssertTrue(result.answer?.contains("Obs: Paminnelseatkomst saknas") == true)
        XCTAssertTrue(result.answer?.contains("Obs: Kontaktatkomst saknas") == true)
        XCTAssertTrue(result.answer?.contains("Obs: Bildatkomst saknas") == true)
        XCTAssertTrue(result.answer?.contains("Obs: Ingen importerad fil-data hittades") == true)
        XCTAssertTrue(result.answer?.contains("Har ar din sammanfattning.") == true)
    }

    func testPipelineUpdatesCheckpointAfterSuccessfulIngest() async throws {
        let recorder = CallRecorder()
        let checkpointStore = MockCheckpointStore(recorder: recorder)

        let pipeline = QueryPipeline(
            interpreter: MockInterpreter(result: QueryInterpretation(
                intent: .summary,
                requiredSources: [.memory],
                timeRange: nil,
                confidence: nil
            )),
            access: MockAccess(),
            fetcher: MockFetcher(
                recorder: recorder,
                result: QueryCollectedData(
                    timeRange: DateInterval(start: Date(), end: Date()),
                    items: [
                        UnifiedItemDTO(
                            id: "contact:item-1",
                            source: "contacts",
                            type: .contact,
                            title: "Alva",
                            body: "alva@example.com",
                            createdAt: Date(),
                            updatedAt: Date(),
                            startAt: nil,
                            endAt: nil,
                            dueAt: nil,
                            status: [:]
                        )
                    ],
                    entries: [],
                    missingAccess: [],
                    checkpointSources: [.contacts, .files]
                )
            ),
            ingestService: MockIngestService(recorder: recorder),
            backendQueryService: MockBackendQueryService(
                recorder: recorder,
                response: BackendLLMResponseDTO(
                    content: "Svar",
                    confidence: nil,
                    sourceDocuments: nil,
                    evidenceItems: nil,
                    usedSources: nil,
                    timeRange: nil
                )
            ),
            checkpointStore: checkpointStore
        )

        _ = try await pipeline.run(UserQuery(text: "test", source: .userTyped))

        XCTAssertEqual(recorder.calls, [
            "collect",
            "ingest",
            "checkpoint:contacts",
            "checkpoint:files",
            "query"
        ])
        XCTAssertEqual(checkpointStore.updatedSources, [.contacts, .files])
    }

    func testPipelineQueriesBackendWhenDeltaIsEmpty() async throws {
        let recorder = CallRecorder()
        let checkpointStore = MockCheckpointStore(recorder: recorder)
        let backend = MockBackendQueryService(
            recorder: recorder,
            response: BackendLLMResponseDTO(
                content: "Svar fran assistant store.",
                confidence: nil,
                sourceDocuments: nil,
                evidenceItems: nil,
                usedSources: ["contacts"],
                timeRange: nil
            )
        )

        let pipeline = QueryPipeline(
            interpreter: MockInterpreter(result: QueryInterpretation(
                intent: .summary,
                requiredSources: [.memory],
                timeRange: nil,
                confidence: nil
            )),
            access: MockAccess(),
            fetcher: MockFetcher(
                recorder: recorder,
                result: QueryCollectedData(
                    timeRange: DateInterval(start: Date(), end: Date()),
                    items: [],
                    entries: [],
                    missingAccess: [],
                    checkpointSources: [.contacts]
                )
            ),
            ingestService: MockIngestService(recorder: recorder),
            backendQueryService: backend,
            checkpointStore: checkpointStore
        )

        let result = try await pipeline.run(UserQuery(text: "Vad vet du om kontakter?", source: .userTyped))

        XCTAssertEqual(result.answer, "Svar fran assistant store.")
        XCTAssertEqual(recorder.calls, ["collect", "query"])
        XCTAssertTrue(checkpointStore.updatedSources.isEmpty)
    }

    func testSecondRunWithEmptyDeltaSkipsIngestButStillQueriesBackend() async throws {
        let recorder = CallRecorder()
        let checkpointStore = MockCheckpointStore(recorder: recorder)
        let backend = MockBackendQueryService(
            recorder: recorder,
            response: BackendLLMResponseDTO(
                content: "Svar fran assistant store.",
                confidence: nil,
                sourceDocuments: nil,
                evidenceItems: nil,
                usedSources: ["contacts", "photos"],
                timeRange: nil
            )
        )

        let firstBatch = QueryCollectedData(
            timeRange: DateInterval(start: Date(), end: Date()),
            items: [
                UnifiedItemDTO(
                    id: "contact:item-1",
                    source: "contacts",
                    type: .contact,
                    title: "Alva",
                    body: "alva@example.com",
                    createdAt: Date(),
                    updatedAt: Date(),
                    startAt: nil,
                    endAt: nil,
                    dueAt: nil,
                    status: [:]
                ),
                UnifiedItemDTO(
                    id: "photo:item-1",
                    source: "photos",
                    type: .photo,
                    title: "Bild",
                    body: "metadata",
                    createdAt: Date(),
                    updatedAt: Date(),
                    startAt: nil,
                    endAt: nil,
                    dueAt: nil,
                    status: [:]
                )
            ],
            entries: [],
            missingAccess: [],
            checkpointSources: [.contacts, .photos]
        )
        let secondBatch = QueryCollectedData(
            timeRange: DateInterval(start: Date(), end: Date()),
            items: [],
            entries: [],
            missingAccess: [],
            checkpointSources: [.contacts, .photos]
        )

        let pipeline = QueryPipeline(
            interpreter: MockInterpreter(result: QueryInterpretation(
                intent: .summary,
                requiredSources: [.memory],
                timeRange: nil,
                confidence: nil
            )),
            access: MockAccess(),
            fetcher: SequenceMockFetcher(recorder: recorder, results: [firstBatch, secondBatch]),
            ingestService: MockIngestService(recorder: recorder),
            backendQueryService: backend,
            checkpointStore: checkpointStore
        )

        _ = try await pipeline.run(UserQuery(text: "forsta", source: .userTyped))
        _ = try await pipeline.run(UserQuery(text: "andra", source: .userTyped))

        XCTAssertEqual(recorder.calls, [
            "collect",
            "ingest",
            "checkpoint:contacts",
            "checkpoint:photos",
            "query",
            "collect",
            "query"
        ])
        XCTAssertEqual(checkpointStore.updatedSources, [.contacts, .photos])
    }
}

private enum MockPipelineError: Error {
    case failedIngest
}

private final class CallRecorder {
    var calls: [String] = []
}

private struct MockInterpreter: QueryInterpreting {
    let result: QueryInterpretation

    func interpret(_ query: UserQuery) async throws -> QueryInterpretation {
        result
    }
}

private struct MockAccess: QuerySourceAccessing {
    func isAllowed(_ source: QuerySource) -> Bool { true }
    func assertAllowed(_ source: QuerySource) throws {}
    func deniedReason(for source: QuerySource) -> String { "" }
}

private final class MockFetcher: QueryDataFetching {
    private let recorder: CallRecorder
    private let result: QueryCollectedData

    init(recorder: CallRecorder, result: QueryCollectedData) {
        self.recorder = recorder
        self.result = result
    }

    func collect(days: Int, access: QuerySourceAccessing) async throws -> QueryCollectedData {
        recorder.calls.append("collect")
        return result
    }
}

private final class SequenceMockFetcher: QueryDataFetching {
    private let recorder: CallRecorder
    private var remaining: [QueryCollectedData]

    init(recorder: CallRecorder, results: [QueryCollectedData]) {
        self.recorder = recorder
        self.remaining = results
    }

    func collect(days: Int, access: QuerySourceAccessing) async throws -> QueryCollectedData {
        recorder.calls.append("collect")
        guard !remaining.isEmpty else {
            return QueryCollectedData(
                timeRange: DateInterval(start: Date(), end: Date()),
                items: [],
                entries: [],
                missingAccess: []
            )
        }
        return remaining.removeFirst()
    }
}

private final class MockIngestService: AssistantIngesting {
    private let recorder: CallRecorder
    private let error: Error?

    init(recorder: CallRecorder, error: Error? = nil) {
        self.recorder = recorder
        self.error = error
    }

    func ingest(items: [UnifiedItemDTO]) async throws {
        recorder.calls.append("ingest")
        if let error {
            throw error
        }
    }
}

private final class MockBackendQueryService: BackendQuerying {
    private let recorder: CallRecorder
    private let response: BackendLLMResponseDTO

    private(set) var lastDays: Int?
    private(set) var lastSources: [String]?

    init(recorder: CallRecorder, response: BackendLLMResponseDTO) {
        self.recorder = recorder
        self.response = response
    }

    func query(
        text: String,
        days: Int,
        sources: [String],
        dataFilter: [String : AnyCodable]?
    ) async throws -> BackendLLMResponseDTO {
        recorder.calls.append("query")
        lastDays = days
        lastSources = sources
        return response
    }
}

private final class MockCheckpointStore: Etapp2IngestCheckpointStoring, @unchecked Sendable {
    private let recorder: CallRecorder
    private(set) var updatedSources: [QuerySource] = []

    init(recorder: CallRecorder) {
        self.recorder = recorder
    }

    func lastCheckpoint(for source: QuerySource) throws -> Date? {
        nil
    }

    func updateCheckpoint(for source: QuerySource, at date: Date) throws {
        updatedSources.append(source)
        recorder.calls.append("checkpoint:\(source.rawValue)")
    }
}

// MARK: - Location Intent Tests

extension BackendQueryPipelineTests {
    
    func testIsLocationIntentDetectsSwedishHints() {
        // Swedish location hints
        XCTAssertTrue(QueryPipeline.isLocationIntent("var är jag just nu?"))
        XCTAssertTrue(QueryPipeline.isLocationIntent("Vad finns nära mig?"))
        XCTAssertTrue(QueryPipeline.isLocationIntent("Finns det restauranger i närheten?"))
        XCTAssertTrue(QueryPipeline.isLocationIntent("Vilken plats är jag på?"))
    }
    
    func testIsLocationIntentDetectsEnglishHints() {
        // English location hints
        XCTAssertTrue(QueryPipeline.isLocationIntent("where am i?"))
        XCTAssertTrue(QueryPipeline.isLocationIntent("What is near me?"))
        XCTAssertTrue(QueryPipeline.isLocationIntent("Restaurants close to me"))
        XCTAssertTrue(QueryPipeline.isLocationIntent("What's nearby?"))
    }
    
    func testIsLocationIntentReturnsFalseForNonLocationQueries() {
        // Non-location queries
        XCTAssertFalse(QueryPipeline.isLocationIntent("Vad har jag för möten idag?"))
        XCTAssertFalse(QueryPipeline.isLocationIntent("Visa mina påminnelser"))
        XCTAssertFalse(QueryPipeline.isLocationIntent("What are my tasks?"))
        XCTAssertFalse(QueryPipeline.isLocationIntent("Hjälp mig med min packlista"))
    }
    
    func testMissingAccessPrefixIncludesLocation() async throws {
        let recorder = CallRecorder()
        
        let pipeline = QueryPipeline(
            interpreter: MockInterpreter(result: QueryInterpretation(
                intent: .summary,
                requiredSources: [.memory],
                timeRange: nil,
                confidence: nil
            )),
            access: MockAccess(),
            fetcher: MockFetcher(
                recorder: recorder,
                result: QueryCollectedData(
                    timeRange: DateInterval(start: Date(), end: Date()),
                    items: [],
                    entries: [],
                    missingAccess: [.location]
                )
            ),
            ingestService: MockIngestService(recorder: CallRecorder()),
            backendQueryService: MockBackendQueryService(
                recorder: CallRecorder(),
                response: BackendLLMResponseDTO(
                    content: "Svar utan plats.",
                    confidence: nil,
                    sourceDocuments: nil,
                    evidenceItems: nil,
                    usedSources: nil,
                    timeRange: nil
                )
            )
        )
        
        let result = try await pipeline.run(UserQuery(text: "var är jag?", source: .userTyped))
        
        XCTAssertTrue(result.answer?.contains("Obs: Platsåtkomst saknas") == true)
    }
}
