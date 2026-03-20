import XCTest
@testable import Helper

@MainActor
final class ChatSuggestionFlowTests: XCTestCase {

    func testAssistantMessageCarriesSuggestionAndLogsSuggestedAction() async {
        let logger = RecordingSuggestionLogger()
        let vm = makeViewModel(
            decision: .suggestion(Self.reminderSuggestion),
            logger: logger
        )

        vm.query = "Kom ihåg att betala hyran"
        await vm.send()

        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages.last?.suggestion?.kind, .reminder)
        XCTAssertEqual(logger.entries.map(\.action.rawValue), [DecisionAction.suggested.rawValue])
    }

    func testDismissSuggestionUpdatesStateAndLogsDismissed() async throws {
        let logger = RecordingSuggestionLogger()
        let vm = makeViewModel(
            decision: .suggestion(Self.noteSuggestion),
            logger: logger
        )

        vm.query = "Portkod: 4582"
        await vm.send()

        let assistantID = try XCTUnwrap(vm.messages.last?.id)
        vm.dismissSuggestion(for: assistantID)

        XCTAssertEqual(vm.messages.last?.suggestion?.state, .dismissed)
        XCTAssertEqual(
            logger.entries.map(\.action.rawValue),
            [DecisionAction.suggested.rawValue, DecisionAction.dismissed.rawValue]
        )
    }

    func testCompleteSuggestionUpdatesStateAndLogsExecuted() async throws {
        let logger = RecordingSuggestionLogger()
        let vm = makeViewModel(
            decision: .suggestion(Self.calendarSuggestion),
            logger: logger
        )

        vm.query = "Boka möte imorgon kl 15"
        await vm.send()

        let assistantID = try XCTUnwrap(vm.messages.last?.id)
        vm.completeSuggestion(for: assistantID)

        XCTAssertEqual(vm.messages.last?.suggestion?.state, .completed)
        XCTAssertEqual(
            logger.entries.map(\.action.rawValue),
            [DecisionAction.suggested.rawValue, DecisionAction.executed.rawValue]
        )
    }

    func testFailSuggestionUpdatesStateToFailed() async throws {
        let vm = makeViewModel(
            decision: .suggestion(Self.reminderSuggestion),
            logger: RecordingSuggestionLogger()
        )

        vm.query = "Kom ihåg att köpa mjölk"
        await vm.send()

        let assistantID = try XCTUnwrap(vm.messages.last?.id)
        vm.failSuggestion(for: assistantID, message: "Påminnelsen kunde inte skapas.")

        XCTAssertEqual(
            vm.messages.last?.suggestion?.state,
            .failed("Påminnelsen kunde inte skapas.")
        )
    }

    func testNoActionDecisionLogsWithoutSuggestion() async {
        let logger = RecordingSuggestionLogger()
        let vm = makeViewModel(
            decision: .noAction(reasons: ["trigger:user_text", "reason:data_query_like"]),
            logger: logger
        )

        vm.query = "Vad har jag idag?"
        await vm.send()

        XCTAssertNil(vm.messages.last?.suggestion)
        XCTAssertEqual(logger.entries.map(\.action.rawValue), [DecisionAction.noAction.rawValue])
    }

    func testSuppressedDecisionLogsSuppressedAction() async {
        let logger = RecordingSuggestionLogger()
        let vm = makeViewModel(
            decision: .suppressed(
                kind: .note,
                confidence: 0.62,
                reasons: ["trigger:user_text", "reason:below_confidence_threshold"]
            ),
            logger: logger
        )

        vm.query = "Bokning till Paris"
        await vm.send()

        XCTAssertNil(vm.messages.last?.suggestion)
        XCTAssertEqual(logger.entries.map(\.action.rawValue), [DecisionAction.suppressed.rawValue])
    }

    private func makeViewModel(
        decision: ChatSuggestionDecision,
        logger: RecordingSuggestionLogger
    ) -> ChatViewModel {
        let plan = BackendIntentPlanDTO(
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
        let pipeline = QueryPipeline(
            backendQueryService: StaticSuggestionBackend(
                response: BackendQueryResponseDTO(
                    intentPlan: plan,
                    answer: "Här är svaret",
                    hasDataIntent: true
                )
            ),
            localCollector: EmptySuggestionCollector(),
            accessGate: AllowingSuggestionAccess()
        )
        return ChatViewModel(
            pipeline: pipeline,
            suggestionEngine: StubSuggestionEngine(decision: decision),
            suggestionLogger: logger
        )
    }

    private static let calendarSuggestion = ChatSuggestionCard(
        kind: .calendar,
        title: "Kalenderförslag",
        explanation: "Vill du lägga det i kalendern?",
        draft: .calendar(
            .init(
                title: "Möte med Sara",
                notes: "",
                startDate: Date(timeIntervalSince1970: 1_742_515_200),
                endDate: Date(timeIntervalSince1970: 1_742_518_800),
                isAllDay: false
            )
        ),
        state: .visible,
        confidence: 0.92,
        auditReasons: ["trigger:user_text", "action_kind:calendar"]
    )

    private static let reminderSuggestion = ChatSuggestionCard(
        kind: .reminder,
        title: "Påminnelseförslag",
        explanation: "Vill du skapa en påminnelse?",
        draft: .reminder(
            .init(
                title: "Betala hyran",
                dueDate: Date(timeIntervalSince1970: 1_742_515_200),
                notes: "",
                location: nil,
                priority: .medium
            )
        ),
        state: .visible,
        confidence: 0.9,
        auditReasons: ["trigger:user_text", "action_kind:reminder"]
    )

    private static let noteSuggestion = ChatSuggestionCard(
        kind: .note,
        title: "Anteckningsförslag",
        explanation: "Vill du spara det som anteckning?",
        draft: .note(
            .init(
                title: "Portkod",
                body: "4582"
            )
        ),
        state: .visible,
        confidence: 0.84,
        auditReasons: ["trigger:user_text", "action_kind:note"]
    )
}

private struct StubSuggestionEngine: ChatSuggestionEvaluating {
    let decision: ChatSuggestionDecision

    func decide(for text: String) -> ChatSuggestionDecision {
        _ = text
        return decision
    }
}

@MainActor
private final class RecordingSuggestionLogger: ChatSuggestionLogging {
    struct Entry {
        let action: DecisionAction
        let messageID: String
        let kind: ChatSuggestionKind?
        let confidence: Double?
        let reasons: [String]
    }

    private(set) var entries: [Entry] = []

    func log(
        action: DecisionAction,
        messageID: String,
        kind: ChatSuggestionKind?,
        confidence: Double?,
        reasons: [String]
    ) {
        entries.append(
            Entry(
                action: action,
                messageID: messageID,
                kind: kind,
                confidence: confidence,
                reasons: reasons
            )
        )
    }
}

private struct StaticSuggestionBackend: BackendQuerying {
    let response: BackendQueryResponseDTO

    func query(text: String) async throws -> BackendQueryResponseDTO {
        _ = text
        return response
    }
}

private struct EmptySuggestionCollector: LocalQueryCollecting {
    func collect(
        source: QuerySource,
        timeRange: DateInterval?,
        intentPlan: BackendIntentPlanDTO,
        userQuery: UserQuery
    ) async throws -> LocalCollectedResult {
        _ = (source, timeRange, intentPlan, userQuery)
        return LocalCollectedResult(entries: [])
    }
}

private struct AllowingSuggestionAccess: QuerySourceAccessChecking {
    func isEnabled(_ source: QuerySource) -> Bool {
        _ = source
        return true
    }

    func isAllowed(_ source: QuerySource) -> Bool {
        _ = source
        return true
    }

    func deniedMessage(for source: QuerySource) -> String? {
        _ = source
        return nil
    }
}
