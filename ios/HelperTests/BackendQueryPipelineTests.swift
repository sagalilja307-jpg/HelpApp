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

    private func makePlan(
        domain: BackendIntentDomain,
        operation: BackendIntentOperation,
        type: BackendTimeScopeType,
        value: String?
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
            filters: [:],
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
    private(set) var lastSource: QuerySource?

    func collect(
        source: QuerySource,
        timeRange: DateInterval?,
        intentPlan: BackendIntentPlanDTO,
        userQuery: UserQuery
    ) async throws -> LocalCollectedResult {
        lastSource = source
        return LocalCollectedResult(entries: [])
    }
}
