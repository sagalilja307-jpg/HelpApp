import XCTest
@testable import Helper

@MainActor
final class ChatIntentVisualizationTests: XCTestCase {

    func testOperationDomainTimeMatrixResolvesExpectedComponents() async {
        let cases: [(BackendIntentDomain, BackendIntentOperation, BackendTimeScopeType, String?, VisualizationComponent)] = [
            (.calendar, .count, .relative, "today", .summaryCards),
            (.calendar, .exists, .relative, "today", .narrative),
            (.calendar, .latest, .relative, "today", .focus),
            (.calendar, .sum, .relative, "today", .summaryCards),
            (.calendar, .sum, .relative, "30d", .heatmap),
            (.calendar, .list, .relative, "today", .timeline),
            (.calendar, .list, .relative, "30d", .weekScroll),
            (.reminders, .list, .relative, "today", .flow),
            (.reminders, .list, .relative, "30d", .groupedList),
            (.photos, .list, .relative, "today", .timeline),
            (.photos, .list, .relative, "30d", .groupedList),
            (.memory, .list, .relative, "today", .timeline),
            (.memory, .list, .relative, "30d", .groupedList),
            (.notes, .list, .relative, "today", .groupedList),
            (.files, .list, .relative, "today", .groupedList),
            (.contacts, .list, .relative, "today", .groupedList),
            (.location, .list, .all, nil, .map)
        ]

        for (domain, operation, scopeType, scopeValue, expected) in cases {
            let plan = makePlan(
                domain: domain,
                operation: operation,
                timeScopeType: scopeType,
                timeScopeValue: scopeValue
            )
            let vm = makeViewModel(plan: plan)
            vm.query = "test"
            await vm.send()

            XCTAssertEqual(
                vm.messages.last?.visualizationComponent,
                expected,
                "Expected \(expected) for domain=\(domain.rawValue), operation=\(operation.rawValue), scope=\(scopeType.rawValue):\(scopeValue ?? "nil")"
            )
        }
    }

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
        let vm = makeViewModel(
            plan: plan,
            hasDataIntent: true,
            answer: "3 olästa mejl."
        )

        vm.query = "hur många olästa mejl har jag?"
        await vm.send()

        XCTAssertEqual(vm.messages.last?.visualizationComponent, .narrative)
    }

    func testMailWithoutDataIntentRendersTextOnly() async {
        let plan = makePlan(
            domain: .mail,
            operation: .count,
            timeScopeType: .all,
            timeScopeValue: nil
        )
        let vm = makeViewModel(
            plan: plan,
            hasDataIntent: false,
            answer: "Text-only fallback."
        )

        vm.query = "mail"
        await vm.send()

        XCTAssertNil(vm.messages.last?.visualizationComponent)
        XCTAssertEqual(vm.messages.last?.text, "Text-only fallback.")
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

    func testAssistantMessageCarriesRenderingDataFromResult() async {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3_600)

        let entry = QueryResult.Entry(
            id: UUID(),
            source: .location,
            title: "Kungstradgarden",
            body: "Observed location",
            date: start,
            latitude: 59.3326,
            longitude: 18.0649
        )

        let plan = makePlan(
            domain: .location,
            operation: .list,
            timeScopeType: .absolute,
            timeScopeValue: nil,
            start: start,
            end: end,
            filters: [
                "status": AnyCodable("unread"),
                "place": AnyCodable("stockholm")
            ]
        )

        let vm = makeViewModel(
            plan: plan,
            collector: FixedCollector(entries: [entry])
        )

        vm.query = "var var jag"
        await vm.send()

        guard let assistant = vm.messages.last else {
            return XCTFail("Expected assistant message")
        }

        XCTAssertEqual(assistant.visualizationComponent, .map)
        XCTAssertEqual(assistant.entries, [entry])
        XCTAssertEqual(assistant.timeRange?.start, start)
        XCTAssertEqual(assistant.timeRange?.end, end)
        XCTAssertEqual(assistant.filters["status"], AnyCodable("unread"))
        XCTAssertEqual(assistant.filters["place"], AnyCodable("stockholm"))
    }

    private func makeViewModel(
        plan: BackendIntentPlanDTO,
        hasDataIntent: Bool = true,
        answer: String? = nil,
        entries: [BackendQueryEntryDTO]? = nil
    ) -> ChatViewModel {
        makeViewModel(
            plan: plan,
            collector: EmptyCollector(),
            hasDataIntent: hasDataIntent,
            answer: answer,
            entries: entries
        )
    }

    private func makeViewModel<C: LocalQueryCollecting>(
        plan: BackendIntentPlanDTO,
        collector: C,
        hasDataIntent: Bool = true,
        answer: String? = nil,
        entries: [BackendQueryEntryDTO]? = nil
    ) -> ChatViewModel {
        let response = BackendQueryResponseDTO(
            intentPlan: plan,
            answer: answer,
            entries: entries,
            hasDataIntent: hasDataIntent
        )
        let pipeline = QueryPipeline(
            backendQueryService: StaticBackend(response: response),
            localCollector: collector,
            accessGate: AllowingAccess()
        )
        return ChatViewModel(pipeline: pipeline)
    }

    private func makePlan(
        domain: BackendIntentDomain,
        operation: BackendIntentOperation,
        timeScopeType: BackendTimeScopeType,
        timeScopeValue: String?,
        start: Date? = nil,
        end: Date? = nil,
        filters: [String: AnyCodable] = ["status": AnyCodable("unread")]
    ) -> BackendIntentPlanDTO {
        BackendIntentPlanDTO(
            domain: domain,
            mode: .info,
            operation: operation,
            timeScope: BackendTimeScopeDTO(
                type: timeScopeType,
                value: timeScopeValue,
                start: start,
                end: end
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

private struct StaticBackend: BackendQuerying {
    let response: BackendQueryResponseDTO

    func query(text: String) async throws -> BackendQueryResponseDTO {
        response
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
        intentPlan: BackendIntentPlanDTO,
        userQuery: UserQuery
    ) async throws -> LocalCollectedResult {
        LocalCollectedResult(entries: [])
    }
}

private struct FixedCollector: LocalQueryCollecting {
    let entries: [QueryResult.Entry]

    func collect(
        source: QuerySource,
        timeRange: DateInterval?,
        intentPlan: BackendIntentPlanDTO,
        userQuery: UserQuery
    ) async throws -> LocalCollectedResult {
        LocalCollectedResult(entries: entries)
    }
}

private struct AllowingAccess: QuerySourceAccessChecking {
    func isEnabled(_ source: QuerySource) -> Bool { true }
    func isAllowed(_ source: QuerySource) -> Bool { true }
    func deniedMessage(for source: QuerySource) -> String? { nil }
}
