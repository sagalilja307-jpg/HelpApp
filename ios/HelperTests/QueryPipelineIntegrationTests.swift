import XCTest
@testable import Helper

@MainActor
final class QueryPipelineIntegrationTests: XCTestCase {

    struct MockBackend: BackendQuerying {
        let plan: BackendIntentPlanDTO
        func query(text: String) async throws -> BackendQueryResponseDTO {
            return BackendQueryResponseDTO(intentPlan: plan)
        }
    }

    struct MockAccess: QuerySourceAccessChecking {
        func isEnabled(_ source: QuerySource) -> Bool { true }
        func isAllowed(_ source: QuerySource) -> Bool { true }
        func deniedMessage(for source: QuerySource) -> String? { nil }
    }

    struct MockCollector: LocalQueryCollecting {
        func collect(source: QuerySource, timeRange: DateInterval?, userQuery: UserQuery) async throws -> LocalCollectedResult {
            let entry = QueryResult.Entry(id: UUID(), source: source, title: "one", body: nil, date: Date())
            return LocalCollectedResult(entries: [entry])
        }
    }

    func testPipelineUsesBackendTimeAndReturnsAnswer() async throws {
        // Arrange
        let now = Date()
        let scope = BackendTimeScopeDTO(
            type: .relative,
            value: "today",
            start: now,
            end: now.addingTimeInterval(3600)
        )
        let plan = BackendIntentPlanDTO(
            domain: .calendar,
            mode: .info,
            operation: .count,
            timeScope: scope,
            filters: [:],
            grouping: nil,
            sort: nil,
            needsClarification: false,
            clarificationMessage: nil,
            suggestions: []
        )
        let backend = MockBackend(plan: plan)
        let access = MockAccess()
        let collector = MockCollector()

        let pipeline = QueryPipeline(backendQueryService: backend, localCollector: collector, accessGate: access)

        let userQuery = UserQuery(text: "Hej", source: .userTyped)

        // Act
        let result = try await pipeline.run(userQuery)

        // Assert
        XCTAssertNotNil(result.answer)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertNotNil(result.timeRange)
        XCTAssertEqual(result.intentPlan, plan)
    }
}
