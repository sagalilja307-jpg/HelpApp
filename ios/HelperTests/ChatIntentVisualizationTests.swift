import XCTest
@testable import Helper

@MainActor
final class ChatIntentVisualizationTests: XCTestCase {

    func testLongRangeRelativeValuesResolveToWeekScroll() async {
        let longValues = ["7d", "30d", "3m", "1y"]

        for value in longValues {
            let plan = makePlan(
                domain: .calendar,
                operation: .list,
                timeScopeType: .relative,
                timeScopeValue: value
            )
            let vm = makeViewModel(plan: plan)

            vm.query = "vad har jag i kalendern?"
            await vm.send()

            XCTAssertEqual(vm.messages.last?.visualizationComponent, .weekScroll, "Expected weekScroll for \(value)")
        }
    }

    func testShortRangeRelativeValuesResolveToTimeline() async {
        let shortValues = [
            "today",
            "today_morning",
            "today_day",
            "today_afternoon",
            "today_evening",
            "tomorrow_morning"
        ]

        for value in shortValues {
            let plan = makePlan(
                domain: .calendar,
                operation: .list,
                timeScopeType: .relative,
                timeScopeValue: value
            )
            let vm = makeViewModel(plan: plan)

            vm.query = "visa kalender"
            await vm.send()

            XCTAssertEqual(vm.messages.last?.visualizationComponent, .timeline, "Expected timeline for \(value)")
        }
    }

    func testAllScopeWithNilValueResolvesCorrectly() async {
        let plan = makePlan(
            domain: .calendar,
            operation: .list,
            timeScopeType: .all,
            timeScopeValue: nil
        )
        let vm = makeViewModel(plan: plan)

        vm.query = "visa allt"
        await vm.send()

        XCTAssertEqual(vm.messages.last?.visualizationComponent, .weekScroll)
    }

    func testMailDomainUsesNarrativePlaceholder() async {
        let plan = makePlan(
            domain: .mail,
            operation: .count,
            timeScopeType: .all,
            timeScopeValue: nil
        )
        let vm = makeViewModel(plan: plan)

        vm.query = "hur många olästa mejl har jag?"
        await vm.send()

        XCTAssertEqual(vm.messages.last?.visualizationComponent, .narrative)
    }

    func testMissingDataIntentRendersTextOnly() async {
        let pipeline = QueryPipeline(
            backendQueryService: FailingBackend(),
            localCollector: EmptyCollector(),
            accessGate: AllowingAccess()
        )
        let vm = ChatViewModel(pipeline: pipeline)

        vm.query = "hej"
        await vm.send()

        XCTAssertNil(vm.messages.last?.visualizationComponent)
        XCTAssertFalse(vm.messages.last?.text.isEmpty ?? true)
    }

    private func makeViewModel(plan: BackendIntentPlanDTO) -> ChatViewModel {
        let pipeline = QueryPipeline(
            backendQueryService: StaticBackend(plan: plan),
            localCollector: EmptyCollector(),
            accessGate: AllowingAccess()
        )
        return ChatViewModel(pipeline: pipeline)
    }

    private func makePlan(
        domain: BackendIntentDomain,
        operation: BackendIntentOperation,
        timeScopeType: BackendTimeScopeType,
        timeScopeValue: String?
    ) -> BackendIntentPlanDTO {
        BackendIntentPlanDTO(
            domain: domain,
            mode: .info,
            operation: operation,
            timeScope: BackendTimeScopeDTO(
                type: timeScopeType,
                value: timeScopeValue,
                start: nil,
                end: nil
            ),
            filters: ["status": AnyCodable("unread")],
            grouping: nil,
            sort: nil,
            needsClarification: false,
            clarificationMessage: nil,
            suggestions: []
        )
    }
}

private struct StaticBackend: BackendQuerying {
    let plan: BackendIntentPlanDTO

    func query(text: String) async throws -> BackendQueryResponseDTO {
        BackendQueryResponseDTO(intentPlan: plan)
    }
}

private struct FailingBackend: BackendQuerying {
    func query(text: String) async throws -> BackendQueryResponseDTO {
        throw URLError(.cannotConnectToHost)
    }
}

private struct EmptyCollector: LocalQueryCollecting {
    func collect(
        source: QuerySource,
        timeRange: DateInterval?,
        userQuery: UserQuery
    ) async throws -> LocalCollectedResult {
        LocalCollectedResult(entries: [])
    }
}

private struct AllowingAccess: QuerySourceAccessChecking {
    func isEnabled(_ source: QuerySource) -> Bool { true }
    func isAllowed(_ source: QuerySource) -> Bool { true }
    func deniedMessage(for source: QuerySource) -> String? { nil }
}
