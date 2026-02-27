import XCTest
@testable import Helper

@MainActor
final class BackendQueryPipelineTests: XCTestCase {

    func testBackendQueryResponseDecodesDataIntentWithRelativeStringValue() throws {
        let json = """
        {
          "data_intent": {
            "domain": "calendar",
            "mode": "info",
            "operation": "list",
            "time_scope": {
              "type": "relative",
              "value": "today_morning"
            },
            "filters": {
              "query": "standup"
            }
          }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try BackendQueryAPIService.decoder.decode(BackendQueryResponseDTO.self, from: data)

        XCTAssertEqual(decoded.intentPlan.domain, .calendar)
        XCTAssertEqual(decoded.intentPlan.operation, .list)
        XCTAssertEqual(decoded.intentPlan.timeScope.type, .relative)
        XCTAssertEqual(decoded.intentPlan.timeScope.value, "today_morning")
        XCTAssertEqual(decoded.intentPlan.filters["query"], AnyCodable("standup"))
        XCTAssertTrue(decoded.hasDataIntent)
    }

    func testBackendQueryResponseDecodesAllWithNilValue() throws {
        let json = """
        {
          "data_intent": {
            "domain": "reminders",
            "mode": "info",
            "operation": "exists",
            "time_scope": {
              "type": "all",
              "value": null
            },
            "filters": {}
          }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try BackendQueryAPIService.decoder.decode(BackendQueryResponseDTO.self, from: data)

        XCTAssertEqual(decoded.intentPlan.domain, .reminders)
        XCTAssertEqual(decoded.intentPlan.timeScope.type, .all)
        XCTAssertNil(decoded.intentPlan.timeScope.value)
        XCTAssertTrue(decoded.hasDataIntent)
    }

    func testBackendQueryResponseDecodesIntentPlanWithoutDataIntentFlag() throws {
        let json = """
        {
          "intent_plan": {
            "domain": "calendar",
            "mode": "info",
            "operation": "count",
            "time_scope": {
              "type": "relative",
              "value": "today"
            },
            "filters": {}
          }
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try BackendQueryAPIService.decoder.decode(BackendQueryResponseDTO.self, from: data)

        XCTAssertEqual(decoded.intentPlan.domain, .calendar)
        XCTAssertFalse(decoded.hasDataIntent)
    }

    func testPipelinePassesThroughIntentPlan() async throws {
        let plan = makePlan(domain: .calendar, operation: .count, type: .relative, value: "today")
        let pipeline = QueryPipeline(
            backendQueryService: MockBackendQueryService(response: BackendQueryResponseDTO(intentPlan: plan)),
            localCollector: RecordingCollector(),
            accessGate: AllowingAccess()
        )

        let result = try await pipeline.run(UserQuery(text: "hur många möten"))

        XCTAssertEqual(result.intentPlan, plan)
    }

    func testPipelineSetsNilIntentPlanWhenBackendFails() async throws {
        let pipeline = QueryPipeline(
            backendQueryService: FailingBackendQueryService(),
            localCollector: RecordingCollector(),
            accessGate: AllowingAccess()
        )

        let result = try await pipeline.run(UserQuery(text: "hej"))

        XCTAssertNil(result.intentPlan)
        XCTAssertNotNil(result.answer)
    }

    func testNotesDomainCollectsViaMemorySource() async throws {
        let collector = RecordingCollector()
        let plan = makePlan(domain: .notes, operation: .list, type: .relative, value: "today")
        let pipeline = QueryPipeline(
            backendQueryService: MockBackendQueryService(response: BackendQueryResponseDTO(intentPlan: plan)),
            localCollector: collector,
            accessGate: AllowingAccess()
        )

        _ = try await pipeline.run(UserQuery(text: "visa mina anteckningar"))

        XCTAssertEqual(collector.lastSource, .memory)
    }

    func testMailWithDataIntentCollectsViaMailSource() async throws {
        let collector = RecordingCollector()
        let plan = makePlan(domain: .mail, operation: .count, type: .all, value: nil)
        let response = BackendQueryResponseDTO(
            intentPlan: plan,
            hasDataIntent: true
        )
        let pipeline = QueryPipeline(
            backendQueryService: MockBackendQueryService(response: response),
            localCollector: collector,
            accessGate: AllowingAccess()
        )

        let result = try await pipeline.run(UserQuery(text: "hur många olästa mejl har jag?"))

        XCTAssertEqual(result.intentPlan, plan)
        XCTAssertEqual(collector.lastSource, .mail)
    }

    func testMailWithoutDataIntentReturnsTextOnlyAndSkipsCollector() async throws {
        let collector = RecordingCollector()
        let plan = makePlan(domain: .mail, operation: .count, type: .all, value: nil)
        let response = BackendQueryResponseDTO(
            intentPlan: plan,
            answer: "Det här ska vara text-only.",
            hasDataIntent: false
        )
        let pipeline = QueryPipeline(
            backendQueryService: MockBackendQueryService(response: response),
            localCollector: collector,
            accessGate: AllowingAccess()
        )

        let result = try await pipeline.run(UserQuery(text: "mail"))

        XCTAssertEqual(result.answer, "Det här ska vara text-only.")
        XCTAssertNil(result.intentPlan)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertNil(collector.lastSource)
    }

    func testPipelineDerivesNextWeekRangeWhenStartEndMissing() async throws {
        let collector = RecordingCollector()
        let plan = makePlan(
            domain: .calendar,
            operation: .list,
            type: .relative,
            value: "next_week"
        )
        let pipeline = QueryPipeline(
            backendQueryService: MockBackendQueryService(response: BackendQueryResponseDTO(intentPlan: plan)),
            localCollector: collector,
            accessGate: AllowingAccess()
        )

        let result = try await pipeline.run(UserQuery(text: "vad gör jag nästa vecka"))

        let range = try XCTUnwrap(result.timeRange)
        XCTAssertNotNil(collector.lastTimeRange)
        XCTAssertEqual(collector.lastTimeRange?.start, range.start)
        XCTAssertEqual(collector.lastTimeRange?.end, range.end)
        XCTAssertGreaterThan(range.duration, 6 * 24 * 3600)
        XCTAssertLessThan(range.duration, 8 * 24 * 3600)
    }

    func testPipelineAppliesEntityFiltersBeforeBuildingAnswer() async throws {
        let collector = RecordingCollector(
            stubEntries: [
                QueryResult.Entry(
                    id: UUID(),
                    source: .calendar,
                    title: "Alva fyller år",
                    body: nil,
                    date: DateService.shared.now()
                ),
                QueryResult.Entry(
                    id: UUID(),
                    source: .calendar,
                    title: "Möte med teamet",
                    body: nil,
                    date: DateService.shared.now()
                )
            ]
        )
        let plan = makePlan(
            domain: .calendar,
            operation: .list,
            type: .all,
            value: nil,
            filters: ["query": AnyCodable("alva")]
        )
        let pipeline = QueryPipeline(
            backendQueryService: MockBackendQueryService(response: BackendQueryResponseDTO(intentPlan: plan)),
            localCollector: collector,
            accessGate: AllowingAccess()
        )

        let result = try await pipeline.run(UserQuery(text: "vilken dag fyller Alva år"))

        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.title, "Alva fyller år")
    }

    func testPipelineAppliesMailSenderFiltersBeforeBuildingAnswer() async throws {
        let collector = RecordingCollector(
            stubEntries: [
                QueryResult.Entry(
                    id: UUID(),
                    source: .mail,
                    title: "Betalning uppdaterad",
                    body: "Från: Klarna <no-reply@klarna.com>\nDin faktura är betald.",
                    date: DateService.shared.now()
                ),
                QueryResult.Entry(
                    id: UUID(),
                    source: .mail,
                    title: "Build passed",
                    body: "Från: GitHub <noreply@github.com>",
                    date: DateService.shared.now()
                )
            ]
        )
        let plan = makePlan(
            domain: .mail,
            operation: .list,
            type: .all,
            value: nil,
            filters: ["from": AnyCodable("klarna")]
        )
        let response = BackendQueryResponseDTO(
            intentPlan: plan,
            hasDataIntent: true
        )
        let pipeline = QueryPipeline(
            backendQueryService: MockBackendQueryService(response: response),
            localCollector: collector,
            accessGate: AllowingAccess()
        )

        let result = try await pipeline.run(UserQuery(text: "Vad har jag för mejl från klarna?"))

        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.title, "Betalning uppdaterad")
    }

    private func makePlan(
        domain: BackendIntentDomain,
        operation: BackendIntentOperation,
        type: BackendTimeScopeType,
        value: String?,
        filters: [String: AnyCodable] = [:]
    ) -> BackendIntentPlanDTO {
        BackendIntentPlanDTO(
            domain: domain,
            mode: .info,
            operation: operation,
            timeScope: BackendTimeScopeDTO(
                type: type,
                value: value,
                start: nil,
                end: nil
            ),
            filters: filters,
            grouping: nil,
            sort: nil,
            needsClarification: false,
            clarificationMessage: nil,
            suggestions: []
        )
    }
}

private struct AllowingAccess: QuerySourceAccessChecking {
    func isEnabled(_ source: QuerySource) -> Bool { true }
    func isAllowed(_ source: QuerySource) -> Bool { true }
    func deniedMessage(for source: QuerySource) -> String? { nil }
}

private final class MockBackendQueryService: BackendQuerying {
    let response: BackendQueryResponseDTO

    init(response: BackendQueryResponseDTO) {
        self.response = response
    }

    func query(text: String) async throws -> BackendQueryResponseDTO {
        response
    }
}

private struct FailingBackendQueryService: BackendQuerying {
    func query(text: String) async throws -> BackendQueryResponseDTO {
        throw URLError(.notConnectedToInternet)
    }
}

private final class RecordingCollector: LocalQueryCollecting {
    private let stubEntries: [QueryResult.Entry]
    private(set) var lastSource: QuerySource?
    private(set) var lastTimeRange: DateInterval?

    init(stubEntries: [QueryResult.Entry] = []) {
        self.stubEntries = stubEntries
    }

    func collect(
        source: QuerySource,
        timeRange: DateInterval?,
        intentPlan: BackendIntentPlanDTO,
        userQuery: UserQuery
    ) async throws -> LocalCollectedResult {
        lastSource = source
        lastTimeRange = timeRange
        return LocalCollectedResult(entries: stubEntries)
    }
}
