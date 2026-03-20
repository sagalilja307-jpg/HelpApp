import XCTest
@testable import Helper

@MainActor
final class ChatClarificationFlowTests: XCTestCase {

    func testClarificationChoiceResubmitsQueryWithExplicitDomain() async throws {
        let clarificationPlan = BackendIntentPlanDTO(
            domain: nil,
            mode: .info,
            operation: .needsClarification,
            timeScope: BackendTimeScopeDTO(
                type: .relative,
                value: "today",
                start: nil,
                end: nil
            ),
            filters: [
                "_confidence": AnyCodable("low"),
                "_candidate_domains": AnyCodable(["calendar", "mail"])
            ],
            grouping: nil,
            sort: nil,
            needsClarification: true,
            clarificationMessage: nil,
            suggestions: []
        )
        let resolvedPlan = BackendIntentPlanDTO(
            domain: .calendar,
            mode: .info,
            operation: .list,
            timeScope: BackendTimeScopeDTO(
                type: .relative,
                value: "today",
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

        let backend = RecordingBackend(responses: [
            BackendQueryResponseDTO(intentPlan: clarificationPlan, hasDataIntent: true),
            BackendQueryResponseDTO(intentPlan: resolvedPlan, hasDataIntent: true),
        ])
        let pipeline = QueryPipeline(
            backendQueryService: backend,
            localCollector: EmptyCollector(),
            accessGate: AllowingAccess()
        )
        let vm = ChatViewModel(pipeline: pipeline)

        vm.query = "Vad händer idag?"
        await vm.send()

        let clarificationMessage = try XCTUnwrap(vm.messages.last)
        await vm.sendClarification(for: clarificationMessage, domain: .calendar)

        XCTAssertEqual(backend.receivedQueries, ["Vad händer idag?", "Vad händer idag i kalendern?"])
        XCTAssertEqual(vm.messages.last?.interpretationHint, "Tolkat som kalender · idag")
    }

    func testReminderClarificationChoiceUsesReminderSuffix() async throws {
        let clarificationPlan = BackendIntentPlanDTO(
            domain: nil,
            mode: .info,
            operation: .needsClarification,
            timeScope: BackendTimeScopeDTO(
                type: .relative,
                value: "today",
                start: nil,
                end: nil
            ),
            filters: [
                "_confidence": AnyCodable("low"),
                "_candidate_domains": AnyCodable(["reminders", "calendar"])
            ],
            grouping: nil,
            sort: nil,
            needsClarification: true,
            clarificationMessage: nil,
            suggestions: []
        )
        let resolvedPlan = BackendIntentPlanDTO(
            domain: .reminders,
            mode: .info,
            operation: .list,
            timeScope: BackendTimeScopeDTO(
                type: .relative,
                value: "today",
                start: nil,
                end: nil
            ),
            filters: ["status": AnyCodable("pending")],
            grouping: nil,
            sort: nil,
            needsClarification: false,
            clarificationMessage: nil,
            suggestions: []
        )

        let backend = RecordingBackend(responses: [
            BackendQueryResponseDTO(intentPlan: clarificationPlan, hasDataIntent: true),
            BackendQueryResponseDTO(intentPlan: resolvedPlan, hasDataIntent: true),
        ])
        let pipeline = QueryPipeline(
            backendQueryService: backend,
            localCollector: EmptyCollector(),
            accessGate: AllowingAccess()
        )
        let vm = ChatViewModel(pipeline: pipeline)

        vm.query = "Vad behöver jag göra idag?"
        await vm.send()

        let clarificationMessage = try XCTUnwrap(vm.messages.last)
        await vm.sendClarification(for: clarificationMessage, domain: .reminders)

        XCTAssertEqual(
            backend.receivedQueries,
            ["Vad behöver jag göra idag?", "Vad behöver jag göra idag i påminnelser?"]
        )
        XCTAssertEqual(vm.messages.last?.interpretationHint, "Tolkat som påminnelser · öppna")
    }

    func testFilesClarificationChoiceUsesFilesSuffix() async throws {
        let clarificationPlan = BackendIntentPlanDTO(
            domain: nil,
            mode: .info,
            operation: .needsClarification,
            timeScope: BackendTimeScopeDTO(
                type: .all,
                value: nil,
                start: nil,
                end: nil
            ),
            filters: [
                "_confidence": AnyCodable("low"),
                "_candidate_domains": AnyCodable(["files", "photos"])
            ],
            grouping: nil,
            sort: nil,
            needsClarification: true,
            clarificationMessage: nil,
            suggestions: []
        )
        let resolvedPlan = BackendIntentPlanDTO(
            domain: .files,
            mode: .info,
            operation: .list,
            timeScope: BackendTimeScopeDTO(
                type: .all,
                value: nil,
                start: nil,
                end: nil
            ),
            filters: ["text_contains": AnyCodable("boardingkort")],
            grouping: nil,
            sort: nil,
            needsClarification: false,
            clarificationMessage: nil,
            suggestions: []
        )

        let backend = RecordingBackend(responses: [
            BackendQueryResponseDTO(intentPlan: clarificationPlan, hasDataIntent: true),
            BackendQueryResponseDTO(intentPlan: resolvedPlan, hasDataIntent: true),
        ])
        let pipeline = QueryPipeline(
            backendQueryService: backend,
            localCollector: EmptyCollector(),
            accessGate: AllowingAccess()
        )
        let vm = ChatViewModel(pipeline: pipeline)

        vm.query = "Har jag sparat boardingkortet?"
        await vm.send()

        let clarificationMessage = try XCTUnwrap(vm.messages.last)
        await vm.sendClarification(for: clarificationMessage, domain: .files)

        XCTAssertEqual(
            backend.receivedQueries,
            ["Har jag sparat boardingkortet?", "Har jag sparat boardingkortet i filerna?"]
        )
        XCTAssertEqual(vm.messages.last?.interpretationHint, "Tolkat som filer · boardingkort")
    }

    func testMemoryClarificationChoiceUsesMemorySuffix() async throws {
        let clarificationPlan = BackendIntentPlanDTO(
            domain: nil,
            mode: .info,
            operation: .needsClarification,
            timeScope: BackendTimeScopeDTO(
                type: .all,
                value: nil,
                start: nil,
                end: nil
            ),
            filters: [
                "_confidence": AnyCodable("low"),
                "_candidate_domains": AnyCodable(["memory", "notes"])
            ],
            grouping: nil,
            sort: nil,
            needsClarification: true,
            clarificationMessage: nil,
            suggestions: []
        )
        let resolvedPlan = BackendIntentPlanDTO(
            domain: .memory,
            mode: .info,
            operation: .list,
            timeScope: BackendTimeScopeDTO(
                type: .all,
                value: nil,
                start: nil,
                end: nil
            ),
            filters: ["text_contains": AnyCodable("resan")],
            grouping: nil,
            sort: nil,
            needsClarification: false,
            clarificationMessage: nil,
            suggestions: []
        )

        let backend = RecordingBackend(responses: [
            BackendQueryResponseDTO(intentPlan: clarificationPlan, hasDataIntent: true),
            BackendQueryResponseDTO(intentPlan: resolvedPlan, hasDataIntent: true),
        ])
        let pipeline = QueryPipeline(
            backendQueryService: backend,
            localCollector: EmptyCollector(),
            accessGate: AllowingAccess()
        )
        let vm = ChatViewModel(pipeline: pipeline)

        vm.query = "Har jag något om resan?"
        await vm.send()

        let clarificationMessage = try XCTUnwrap(vm.messages.last)
        await vm.sendClarification(for: clarificationMessage, domain: .memory)

        XCTAssertEqual(
            backend.receivedQueries,
            ["Har jag något om resan?", "Har jag något om resan i minnet?"]
        )
        XCTAssertEqual(vm.messages.last?.interpretationHint, "Tolkat som minne · resan")
    }

    func testHealthClarificationChoiceUsesHealthSuffix() async throws {
        let clarificationPlan = BackendIntentPlanDTO(
            domain: nil,
            mode: .info,
            operation: .needsClarification,
            timeScope: BackendTimeScopeDTO(
                type: .relative,
                value: "yesterday",
                start: nil,
                end: nil
            ),
            filters: [
                "_confidence": AnyCodable("low"),
                "_candidate_domains": AnyCodable(["location", "health"])
            ],
            grouping: nil,
            sort: nil,
            needsClarification: true,
            clarificationMessage: nil,
            suggestions: []
        )
        let resolvedPlan = BackendIntentPlanDTO(
            domain: .health,
            mode: .info,
            operation: .count,
            timeScope: BackendTimeScopeDTO(
                type: .relative,
                value: "yesterday",
                start: nil,
                end: nil
            ),
            filters: [
                "metric": AnyCodable("workout"),
                "workout_type": AnyCodable("running")
            ],
            grouping: nil,
            sort: nil,
            needsClarification: false,
            clarificationMessage: nil,
            suggestions: []
        )

        let backend = RecordingBackend(responses: [
            BackendQueryResponseDTO(intentPlan: clarificationPlan, hasDataIntent: true),
            BackendQueryResponseDTO(intentPlan: resolvedPlan, hasDataIntent: true),
        ])
        let pipeline = QueryPipeline(
            backendQueryService: backend,
            localCollector: EmptyCollector(),
            accessGate: AllowingAccess()
        )
        let vm = ChatViewModel(pipeline: pipeline)

        vm.query = "Var tränade jag igår?"
        await vm.send()

        let clarificationMessage = try XCTUnwrap(vm.messages.last)
        await vm.sendClarification(for: clarificationMessage, domain: .health)

        XCTAssertEqual(
            backend.receivedQueries,
            ["Var tränade jag igår?", "Var tränade jag igår i hälsodatan?"]
        )
        XCTAssertEqual(vm.messages.last?.interpretationHint, "Tolkat som hälsa · löpning · igår")
    }
}

private final class RecordingBackend: BackendQuerying {
    private var responses: [BackendQueryResponseDTO]
    private(set) var receivedQueries: [String] = []

    init(responses: [BackendQueryResponseDTO]) {
        self.responses = responses
    }

    func query(text: String) async throws -> BackendQueryResponseDTO {
        receivedQueries.append(text)
        return responses.removeFirst()
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

private struct AllowingAccess: QuerySourceAccessChecking {
    func isEnabled(_ source: QuerySource) -> Bool { true }
    func isAllowed(_ source: QuerySource) -> Bool { true }
    func deniedMessage(for source: QuerySource) -> String? { nil }
}
