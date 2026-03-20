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
    }

    func testReminderTextProducesReminderSuggestion() {
        let engine = makeEngine()

        let decision = engine.decide(for: "Kom ihåg att betala hyran imorgon")

        guard case .suggestion(let suggestion) = decision else {
            return XCTFail("Expected suggestion")
        }
        XCTAssertEqual(suggestion.kind, .reminder)
    }

    func testReferenceInfoProducesNoteSuggestion() {
        let engine = makeEngine()

        let decision = engine.decide(for: "Portkod: 4582 till gården")

        guard case .suggestion(let suggestion) = decision else {
            return XCTFail("Expected suggestion")
        }
        XCTAssertEqual(suggestion.kind, .note)
    }

    func testDataQueryLikeTextProducesNoAction() {
        let engine = makeEngine()

        let decision = engine.decide(for: "Vad har jag idag?")

        guard case .noAction(let reasons) = decision else {
            return XCTFail("Expected noAction")
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
