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

    func testImmediateCalendarCreateSuggestionSkipsQueryPipeline() async {
        let logger = RecordingSuggestionLogger()
        let backend = CountingSuggestionBackend(
            response: BackendQueryResponseDTO(
                intentPlan: Self.plan,
                answer: "Det här ska inte användas",
                hasDataIntent: true
            )
        )
        let pipeline = QueryPipeline(
            backendQueryService: backend,
            localCollector: EmptySuggestionCollector(),
            accessGate: AllowingSuggestionAccess()
        )
        let vm = ChatViewModel(
            pipeline: pipeline,
            suggestionEngine: StubSuggestionEngine(decision: .suggestion(Self.createCalendarSuggestion)),
            suggestionLogger: logger
        )

        vm.query = "Jag ska tvätta imorgon kl 10-13 kan du lägga in i kalendern?"
        await vm.send()

        XCTAssertEqual(backend.callCount, 0)
        XCTAssertEqual(vm.messages.last?.text, "Jag kan lägga in det här i kalendern. Vill du öppna utkastet?")
        XCTAssertEqual(vm.messages.last?.suggestion?.kind, .calendar)
    }

    func testRealEngineWriteInCalendarQuerySkipsQueryPipeline() async {
        let logger = RecordingSuggestionLogger()
        let backend = CountingSuggestionBackend(
            response: BackendQueryResponseDTO(
                intentPlan: Self.plan,
                answer: "Jag är inte helt säker ännu. Menar du kalender eller mejl?",
                hasDataIntent: true
            )
        )
        let pipeline = QueryPipeline(
            backendQueryService: backend,
            localCollector: EmptySuggestionCollector(),
            accessGate: AllowingSuggestionAccess()
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let vm = ChatViewModel(
            pipeline: pipeline,
            suggestionEngine: ChatSuggestionEngine(
                nowProvider: { Self.fixedNow },
                calendar: calendar
            ),
            suggestionLogger: logger
        )

        vm.query = "Kan du skriva in tvätta imorgon kl 10-13 i kalendern?"
        await vm.send()

        XCTAssertEqual(backend.callCount, 0)
        XCTAssertEqual(vm.messages.last?.text, "Jag kan lägga in det här i kalendern. Vill du öppna utkastet?")
        XCTAssertEqual(vm.messages.last?.suggestion?.kind, .calendar)
        XCTAssertEqual(vm.messages.last?.suggestion?.title, "Tvätta")
    }

    func testImmediateFollowUpSuggestionSkipsQueryPipeline() async {
        let logger = RecordingSuggestionLogger()
        let backend = CountingSuggestionBackend(
            response: BackendQueryResponseDTO(
                intentPlan: Self.plan,
                answer: "Det här ska inte användas",
                hasDataIntent: true
            )
        )
        let pipeline = QueryPipeline(
            backendQueryService: backend,
            localCollector: EmptySuggestionCollector(),
            accessGate: AllowingSuggestionAccess()
        )
        let vm = ChatViewModel(
            pipeline: pipeline,
            suggestionEngine: StubSuggestionEngine(decision: .suggestion(Self.followUpSuggestion)),
            suggestionLogger: logger
        )

        vm.query = "Jag mejlade Sara och väntar på svar"
        await vm.send()

        XCTAssertEqual(backend.callCount, 0)
        XCTAssertEqual(vm.messages.last?.text, "Jag kan lägga upp en uppföljning åt dig. Vill du öppna utkastet?")
        XCTAssertEqual(vm.messages.last?.suggestion?.kind, .followUp)
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
        let pipeline = QueryPipeline(
            backendQueryService: StaticSuggestionBackend(
                response: BackendQueryResponseDTO(
                    intentPlan: Self.plan,
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

    private static let plan = BackendIntentPlanDTO(
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

    private static let createCalendarSuggestion = ChatSuggestionCard(
        kind: .calendar,
        title: "Kalenderförslag",
        explanation: "Vill du lägga det i kalendern?",
        draft: .calendar(
            .init(
                title: "Tvätta",
                notes: "",
                startDate: Date(timeIntervalSince1970: 1_742_601_600),
                endDate: Date(timeIntervalSince1970: 1_742_612_400),
                isAllDay: false
            )
        ),
        state: .visible,
        confidence: 0.97,
        auditReasons: ["trigger:user_text", "action_kind:calendar", "intent:create_request"]
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
                priority: .medium,
                listName: nil
            )
        ),
        state: .visible,
        confidence: 0.9,
        auditReasons: ["trigger:user_text", "action_kind:reminder"]
    )

    private static let fixedNow = Date(timeIntervalSince1970: 1_742_428_800)

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

    private static let followUpSuggestion = ChatSuggestionCard(
        kind: .followUp,
        title: "Uppföljningsförslag",
        explanation: "Vill du skapa en uppföljning?",
        draft: .followUp(
            .init(
                title: "Följ upp med Sara",
                draftText: "Hej Sara! Jag ville bara följa upp mitt tidigare meddelande.",
                contextText: "Väntar på svar från Sara.",
                waitingSince: Date(timeIntervalSince1970: 1_742_428_800),
                eligibleAt: Date(timeIntervalSince1970: 1_742_515_200),
                dueAt: Date(timeIntervalSince1970: 1_742_547_600),
                clusterID: nil
            )
        ),
        state: .visible,
        confidence: 0.91,
        auditReasons: [
            "trigger:user_text",
            "action_kind:follow_up",
            "heuristic:waiting_for_response",
            "intent:follow_up_request"
        ]
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

@MainActor
private final class CountingSuggestionBackend: BackendQuerying {
    let response: BackendQueryResponseDTO
    private(set) var callCount = 0

    init(response: BackendQueryResponseDTO) {
        self.response = response
    }

    func query(text: String) async throws -> BackendQueryResponseDTO {
        _ = text
        callCount += 1
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
