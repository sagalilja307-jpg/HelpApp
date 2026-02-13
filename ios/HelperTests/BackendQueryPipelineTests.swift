import XCTest
@testable import Helper

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
                    missingAccess: [.calendar, .reminders]
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
        XCTAssertTrue(result.answer?.contains("Har ar din sammanfattning.") == true)
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
