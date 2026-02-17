import XCTest
@testable import Helper

@MainActor
final class BackendQueryPipelineTests: XCTestCase {

    func testBackendResponseDecodesNaiveDatesAndAnalysis() throws {
        let json = """
        {
          "content": "Jag hittade 1 kalenderhändelse i den perioden.",
          "confidence": 0.95,
          "analysis_ready": true,
          "requires_sources": [],
          "requirement_reason_codes": [],
          "required_time_window": null,
          "evidence_items": [
            {
              "id": "evt-1",
              "source": "calendar",
              "type": "event",
              "title": "Team standup",
              "body": "Daily sync",
              "date": "2026-02-17T09:00:00",
              "url": null
            }
          ],
          "time_range": {
            "start": "2026-02-17T00:00:00",
            "end": "2026-02-17T23:59:59",
            "days": 1
          },
          "analysis": {
            "intent_id": "calendar.specific_day_query",
            "time_window": {
              "start": "2026-02-17T00:00:00",
              "end": "2026-02-17T23:59:59",
              "granularity": "day"
            },
            "insights": [
              { "metric": "event_count", "value": 1 }
            ],
            "patterns": [],
            "limitations": [],
            "confidence": 0.95
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let decoded = try BackendQueryAPIService.decoder.decode(BackendLLMResponseDTO.self, from: data)

        XCTAssertEqual(decoded.content, "Jag hittade 1 kalenderhändelse i den perioden.")
        XCTAssertEqual(decoded.timeRange?.days, 1)
        XCTAssertEqual(decoded.analysis?.intentId, "calendar.specific_day_query")
        XCTAssertEqual(decoded.analysis?.timeWindow.granularity, "day")
        XCTAssertEqual(decoded.analysisReady, true)
        XCTAssertEqual(decoded.requiresSources, [])
        XCTAssertEqual(decoded.requirementReasonCodes, [])
        XCTAssertEqual(decoded.evidenceItems?.first?.title, "Team standup")
    }

    func testBackendResponseDecodesWhenSourceGatingFieldsAreMissing() throws {
        let json = """
        {
          "content": "Hej"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try BackendQueryAPIService.decoder.decode(BackendLLMResponseDTO.self, from: data)

        XCTAssertEqual(decoded.content, "Hej")
        XCTAssertNil(decoded.analysisReady)
        XCTAssertNil(decoded.requiresSources)
        XCTAssertNil(decoded.requirementReasonCodes)
        XCTAssertNil(decoded.requiredTimeWindow)
    }

    func testBackendQueryRequestEncodesQueryAndQuestion() throws {
        let request = BackendQueryRequestDTO(
            query: "Vad gjorde jag igår?",
            question: "Vad gjorde jag igår?",
            language: "sv",
            sources: ["assistant_store"],
            days: 7,
            dataFilter: nil
        )
        let data = try BackendQueryAPIService.encoder.encode(request)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(jsonObject["query"] as? String, "Vad gjorde jag igår?")
        XCTAssertEqual(jsonObject["question"] as? String, "Vad gjorde jag igår?")
        XCTAssertEqual(jsonObject["language"] as? String, "sv")
    }

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

    func testCalendarRequirementTriggersSingleAutoRetry() async throws {
        let recorder = CallRecorder()
        let backend = SequenceMockBackendQueryService(
            recorder: recorder,
            responses: [
                BackendLLMResponseDTO(
                    content: "Need calendar",
                    confidence: nil,
                    sourceDocuments: nil,
                    evidenceItems: nil,
                    usedSources: nil,
                    timeRange: nil,
                    analysis: nil,
                    analysisReady: false,
                    requiresSources: ["calendar"],
                    requirementReasonCodes: ["calendar_data_missing"],
                    requiredTimeWindow: BackendRequiredTimeWindowDTO(
                        start: Date(timeIntervalSince1970: 1000),
                        end: Date(timeIntervalSince1970: 2000),
                        granularity: "day"
                    )
                ),
                BackendLLMResponseDTO(
                    content: "Ready after ingest",
                    confidence: nil,
                    sourceDocuments: nil,
                    evidenceItems: nil,
                    usedSources: nil,
                    timeRange: nil,
                    analysis: nil,
                    analysisReady: true,
                    requiresSources: [],
                    requirementReasonCodes: [],
                    requiredTimeWindow: nil
                ),
            ]
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
                    missingAccess: []
                )
            ),
            ingestService: MockIngestService(recorder: recorder),
            backendQueryService: backend,
            calendarFeatureBuilder: MockCalendarFeatureBuilder(
                events: [
                    CalendarFeatureEventIngestDTO(
                        id: "calendar:evt-1",
                        eventIdentifier: "evt-1",
                        title: "Mote",
                        notes: nil,
                        location: nil,
                        startAt: Date(),
                        endAt: Date().addingTimeInterval(3600),
                        isAllDay: false,
                        calendarTitle: "Work",
                        lastModifiedAt: Date(),
                        snapshotHash: "sha256:test"
                    )
                ]
            )
        )

        let result = try await pipeline.run(UserQuery(text: "Vad gjorde jag idag?", source: .userTyped))

        XCTAssertEqual(recorder.calls, ["collect", "query", "ingest_features", "query"])
        XCTAssertEqual(backend.callCount, 2)
        XCTAssertEqual(result.answer, "Ready after ingest")
    }

    func testNoRetryLoopWhenCalendarPermissionIsDenied() async throws {
        let recorder = CallRecorder()
        let backend = SequenceMockBackendQueryService(
            recorder: recorder,
            responses: [
                BackendLLMResponseDTO(
                    content: "Need calendar",
                    confidence: nil,
                    sourceDocuments: nil,
                    evidenceItems: nil,
                    usedSources: nil,
                    timeRange: nil,
                    analysis: nil,
                    analysisReady: false,
                    requiresSources: ["calendar"],
                    requirementReasonCodes: ["calendar_data_missing"],
                    requiredTimeWindow: nil
                )
            ]
        )

        let pipeline = QueryPipeline(
            interpreter: MockInterpreter(result: QueryInterpretation(
                intent: .summary,
                requiredSources: [.memory],
                timeRange: nil,
                confidence: nil
            )),
            access: MockAccessWithCalendarDenied(),
            fetcher: MockFetcher(
                recorder: recorder,
                result: QueryCollectedData(
                    timeRange: DateInterval(start: Date(), end: Date()),
                    items: [],
                    entries: [],
                    missingAccess: []
                )
            ),
            ingestService: MockIngestService(recorder: recorder),
            backendQueryService: backend
        )

        let result = try await pipeline.run(UserQuery(text: "Vad gjorde jag idag?", source: .userTyped))

        XCTAssertEqual(recorder.calls, ["collect", "query"])
        XCTAssertEqual(backend.callCount, 1)
        XCTAssertTrue(result.answer?.contains("Kalenderåtkomst saknas") == true)
    }

    func testHybridPreflightUsesFeatureStatusWhenLastIntentIsCalendar() async throws {
        let recorder = CallRecorder()
        let backend = SequenceMockBackendQueryService(
            recorder: recorder,
            responses: [
                BackendLLMResponseDTO(
                    content: "Calendar analytics ready",
                    confidence: nil,
                    sourceDocuments: nil,
                    evidenceItems: nil,
                    usedSources: nil,
                    timeRange: nil,
                    analysis: BackendAnalysisDTO(
                        intentId: "calendar.specific_day_query",
                        timeWindow: BackendAnalysisTimeWindowDTO(
                            start: Date(),
                            end: Date(),
                            granularity: "day"
                        ),
                        insights: [],
                        patterns: [],
                        limitations: [],
                        confidence: nil
                    ),
                    analysisReady: true,
                    requiresSources: [],
                    requirementReasonCodes: [],
                    requiredTimeWindow: nil
                )
            ]
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
                    missingAccess: []
                )
            ),
            ingestService: MockIngestService(recorder: recorder),
            backendQueryService: backend,
            featureStatusService: MockFeatureStatusService(
                status: BackendFeatureStatusDTO(
                    calendar: BackendCalendarFeatureStatusDTO(
                        available: false,
                        lastUpdated: nil,
                        coverageStart: nil,
                        coverageEnd: nil,
                        coverageDays: nil,
                        snapshotCount: 0,
                        fresh: false,
                        freshnessTTLHours: 24
                    )
                )
            ),
            calendarFeatureBuilder: MockCalendarFeatureBuilder(
                events: [
                    CalendarFeatureEventIngestDTO(
                        id: "calendar:evt-2",
                        eventIdentifier: "evt-2",
                        title: "Mote",
                        notes: nil,
                        location: nil,
                        startAt: Date(),
                        endAt: Date().addingTimeInterval(1800),
                        isAllDay: false,
                        calendarTitle: "Work",
                        lastModifiedAt: Date(),
                        snapshotHash: "sha256:test-2"
                    )
                ]
            )
        )

        _ = try await pipeline.run(
            UserQuery(text: "Vad gjorde jag igår?", source: .userTyped),
            lastBackendAnalyticsIntent: "calendar.specific_day_query"
        )

        XCTAssertEqual(recorder.calls, ["ingest_features", "collect", "query"])
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

private struct MockAccessWithCalendarDenied: QuerySourceAccessing {
    func isAllowed(_ source: QuerySource) -> Bool {
        source != .calendar
    }
    func assertAllowed(_ source: QuerySource) throws {}
    func deniedReason(for source: QuerySource) -> String { "Calendar denied" }
}

private final class MockFetcher: QueryDataFetching {
    private let recorder: CallRecorder
    private let result: QueryCollectedData

    init(recorder: CallRecorder, result: QueryCollectedData) {
        self.recorder = recorder
        self.result = result
    }

    func collect(days: Int, access: QuerySourceAccessing) async throws -> QueryCollectedData {
        return try await collect(days: days, access: access, options: .default)
    }

    func collect(days: Int, access: QuerySourceAccessing, options: QueryCollectionOptions) async throws -> QueryCollectedData {
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
        return try await collect(days: days, access: access, options: .default)
    }

    func collect(days: Int, access: QuerySourceAccessing, options: QueryCollectionOptions) async throws -> QueryCollectedData {
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

    func ingest(items: [UnifiedItemDTO], features: IngestFeaturesDTO?) async throws {
        if features != nil, items.isEmpty {
            recorder.calls.append("ingest_features")
        } else {
            recorder.calls.append("ingest")
        }
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

private final class SequenceMockBackendQueryService: BackendQuerying {
    private let recorder: CallRecorder
    private var responses: [BackendLLMResponseDTO]
    private(set) var callCount = 0

    init(recorder: CallRecorder, responses: [BackendLLMResponseDTO]) {
        self.recorder = recorder
        self.responses = responses
    }

    func query(
        text: String,
        days: Int,
        sources: [String],
        dataFilter: [String : AnyCodable]?
    ) async throws -> BackendLLMResponseDTO {
        _ = text
        _ = days
        _ = sources
        _ = dataFilter
        recorder.calls.append("query")
        callCount += 1
        guard !responses.isEmpty else {
            return BackendLLMResponseDTO(
                content: "fallback",
                confidence: nil,
                sourceDocuments: nil,
                evidenceItems: nil,
                usedSources: nil,
                timeRange: nil
            )
        }
        return responses.removeFirst()
    }
}

private struct MockFeatureStatusService: FeatureStatusFetching {
    let status: BackendFeatureStatusDTO
    let error: Error?

    init(status: BackendFeatureStatusDTO, error: Error? = nil) {
        self.status = status
        self.error = error
    }

    func fetchFeatureStatus() async throws -> BackendFeatureStatusDTO {
        if let error {
            throw error
        }
        return status
    }
}

private struct MockCalendarFeatureBuilder: CalendarFeatureBuilding {
    let events: [CalendarFeatureEventIngestDTO]

    func buildFeatures(in interval: DateInterval) async throws -> [CalendarFeatureEventIngestDTO] {
        _ = interval
        return events
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
