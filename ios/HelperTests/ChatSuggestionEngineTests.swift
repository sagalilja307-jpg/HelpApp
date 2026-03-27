import XCTest
@testable import Helper

final class ChatSuggestionEngineTests: XCTestCase {

    func testCalendarTextProducesCalendarSuggestion() {
        let engine = makeEngine()

        let decision = engine.decide(for: "Boka möte med Sara imorgon kl 15")

        guard case .suggestion(let suggestion) = decision else {
            return XCTFail("Expected suggestion")
        }
        XCTAssertEqual(suggestion.kind, .calendar)
        XCTAssertEqual(suggestion.title, "Möte med Sara")
    }

    func testExplicitCalendarCreateQueryProducesCalendarSuggestionWithTimeRange() throws {
        let engine = makeEngine()

        let decision = engine.decide(for: "Jag ska tvätta imorgon kl 10-13 kan du lägga in i kalendern?")

        guard case .suggestion(let suggestion) = decision else {
            return XCTFail("Expected suggestion")
        }
        guard case .calendar(let draft) = suggestion.draft else {
            return XCTFail("Expected calendar draft")
        }

        XCTAssertEqual(suggestion.kind, .calendar)
        XCTAssertEqual(suggestion.title, "Tvätta")
        XCTAssertTrue(suggestion.auditReasons.contains("intent:create_request"))
        XCTAssertEqual(draft.title, "Tvätta")
        XCTAssertEqual(draft.endDate.timeIntervalSince(draft.startDate), 3 * 60 * 60, accuracy: 1)
        XCTAssertFalse(draft.isAllDay)
    }

    func testReminderTextProducesReminderSuggestion() {
        let engine = makeEngine()

        let decision = engine.decide(for: "Kom ihåg att betala hyran imorgon")

        guard case .suggestion(let suggestion) = decision else {
            return XCTFail("Expected suggestion")
        }
        XCTAssertEqual(suggestion.kind, .reminder)
        XCTAssertEqual(suggestion.title, "Betala hyran")
    }

    func testSmsErrandProducesReminderSuggestion() {
        let engine = makeEngine()

        let decision = engine.decide(for: "Kan du hämta paketet på lördag?")

        guard case .suggestion(let suggestion) = decision else {
            return XCTFail("Expected suggestion")
        }
        guard case .reminder(let draft) = suggestion.draft else {
            return XCTFail("Expected reminder draft")
        }

        XCTAssertEqual(suggestion.kind, .reminder)
        XCTAssertEqual(suggestion.title, "Hämta paketet")
        XCTAssertEqual(draft.title, "Hämta paketet")
        XCTAssertNotNil(draft.dueDate)
    }

    func testChecklistUsesFirstActionableLineForReminderTitle() {
        let engine = makeEngine()

        let decision = engine.decide(for: """
        Klar åtgärder kvar:
        □ Svara jobb
        □ Fråga om datum 4/6
        """)

        guard case .suggestion(let suggestion) = decision else {
            return XCTFail("Expected suggestion")
        }

        XCTAssertEqual(suggestion.kind, .reminder)
        XCTAssertEqual(suggestion.title, "Svara jobb")
    }

    func testAvailabilitySmsProducesCalendarSuggestion() {
        let engine = makeEngine()

        let decision = engine.decide(for: "Kan du på lördag kl 11-13:30?")

        guard case .suggestion(let suggestion) = decision else {
            return XCTFail("Expected suggestion")
        }
        guard case .calendar(let draft) = suggestion.draft else {
            return XCTFail("Expected calendar draft")
        }

        XCTAssertEqual(suggestion.kind, .calendar)
        XCTAssertEqual(suggestion.title, "Plan på lördag")
        XCTAssertEqual(draft.title, "Plan på lördag")
        XCTAssertEqual(draft.endDate.timeIntervalSince(draft.startDate), 2.5 * 60 * 60, accuracy: 1)
    }

    func testInviteSmsProducesFriendlyCalendarTitle() {
        let engine = makeEngine()

        let decision = engine.decide(for: "Ska vi träffas på lördag kl 15?")

        guard case .suggestion(let suggestion) = decision else {
            return XCTFail("Expected suggestion")
        }

        XCTAssertEqual(suggestion.kind, .calendar)
        XCTAssertEqual(suggestion.title, "Träff")
    }

    func testWaitingForResponseTextProducesFollowUpSuggestion() {
        let engine = makeEngine()

        let decision = engine.decide(for: "Jag mejlade Sara igår och väntar på svar, kan du påminna mig att följa upp?")

        guard case .suggestion(let suggestion) = decision else {
            return XCTFail("Expected suggestion")
        }
        guard case .followUp(let draft) = suggestion.draft else {
            return XCTFail("Expected follow up draft")
        }

        XCTAssertEqual(suggestion.kind, .followUp)
        XCTAssertEqual(suggestion.title, "Följ upp med Sara")
        XCTAssertEqual(draft.title, "Följ upp med Sara")
        XCTAssertEqual(draft.eligibleAt.timeIntervalSince(draft.waitingSince), 24 * 60 * 60, accuracy: 1)
        XCTAssertEqual(
            draft.dueAt,
            Date(timeIntervalSince1970: 1_742_547_600)
        )
        XCTAssertTrue(suggestion.auditReasons.contains("heuristic:waiting_for_response"))
        XCTAssertTrue(suggestion.auditReasons.contains("due_policy:24h_then_next_09"))
    }

    func testReferenceInfoProducesNoteSuggestion() {
        let engine = makeEngine()

        let decision = engine.decide(for: "Wifi hemma: Telia-5G")

        guard case .suggestion(let suggestion) = decision else {
            return XCTFail("Expected suggestion")
        }
        XCTAssertEqual(suggestion.kind, .note)
        XCTAssertEqual(suggestion.title, "Wifi hemma")
        guard case .note(let draft) = suggestion.draft else {
            return XCTFail("Expected note draft")
        }
        XCTAssertEqual(draft.title, "Wifi hemma")
        XCTAssertEqual(draft.body, "Telia-5G")
    }

    func testExplicitNoteCommandProducesNoteSuggestion() {
        let engine = makeEngine()

        let decision = engine.decide(for: "Skapa ny anteckning: Packlista för resan")

        guard case .suggestion(let suggestion) = decision else {
            return XCTFail("Expected suggestion")
        }
        guard case .note(let draft) = suggestion.draft else {
            return XCTFail("Expected note draft")
        }

        XCTAssertEqual(suggestion.kind, .note)
        XCTAssertEqual(suggestion.title, "Packlista för resan")
        XCTAssertEqual(draft.title, "Packlista för resan")
        XCTAssertEqual(draft.body, "Packlista för resan")
    }

    func testDataQueryLikeTextProducesNoAction() {
        let engine = makeEngine()

        let decision = engine.decide(for: "Vad har jag idag?")

        guard case .noAction(let reasons) = decision else {
            return XCTFail("Expected noAction")
        }
        XCTAssertTrue(reasons.contains("reason:data_query_like"))
    }

    func testDataQueryDoesNotProduceFollowUpSuggestion() {
        let engine = makeEngine()

        let decision = engine.decide(for: "När svarade Sara senast på mitt mejl?")

        guard case .noAction(let reasons) = decision else {
            return XCTFail("Expected no action")
        }
        XCTAssertTrue(reasons.contains("reason:data_query_like"))
    }

    func testCalendarWinsWhenMultipleSignalsMatch() {
        let engine = makeEngine()

        let decision = engine.decide(for: "Boka möte med Sara imorgon kl 15 och kom ihåg att skicka agenda")

        guard case .suggestion(let suggestion) = decision else {
            return XCTFail("Expected suggestion")
        }
        XCTAssertEqual(suggestion.kind, .calendar)
    }

    func testDisabledPolicySuppressesSuggestions() {
        let engine = ChatSuggestionEngine(
            policy: ChatSuggestionPolicy(
                isEnabled: false,
                minimumConfidence: 0.75,
                maximumSuggestionsPerTurn: 1
            ),
            nowProvider: { Self.fixedNow }
        )

        let decision = engine.decide(for: "Kom ihåg att boka tandläkaren")

        guard case .suppressed(let kind, _, let reasons) = decision else {
            return XCTFail("Expected suppressed")
        }
        XCTAssertNil(kind)
        XCTAssertTrue(reasons.contains("reason:suggestions_disabled"))
    }

    private func makeEngine() -> ChatSuggestionEngine {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return ChatSuggestionEngine(
            nowProvider: { Self.fixedNow },
            calendar: calendar
        )
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_742_428_800)
}
