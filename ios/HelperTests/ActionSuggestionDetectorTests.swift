import XCTest
@testable import Helper

final class ActionSuggestionDetectorTests: XCTestCase {

    func testCalendarTextProducesProposedCalendarAction() {
        let detector = makeDetector()

        let decision = detector.decide(for: "Boka möte med Sara imorgon kl 15")

        guard case .proposed(let action) = decision else {
            return XCTFail("Expected proposed action")
        }
        XCTAssertEqual(action.kind, .calendar)
        XCTAssertEqual(action.title, "Möte med Sara")
    }

    func testDataQueryLikeTextProducesNoAction() {
        let detector = makeDetector()

        let decision = detector.decide(for: "Vad har jag idag?")

        guard case .noAction(let reasons) = decision else {
            return XCTFail("Expected noAction")
        }
        XCTAssertTrue(reasons.contains("reason:data_query_like"))
    }

    func testWaitingForResponseTextProducesFollowUpAction() {
        let detector = makeDetector()

        let decision = detector.decide(
            for: "Jag mejlade Sara igår och väntar på svar, kan du påminna mig att följa upp?"
        )

        guard case .proposed(let action) = decision else {
            return XCTFail("Expected proposed action")
        }
        guard case .followUp(let draft) = action.draft else {
            return XCTFail("Expected follow up draft")
        }

        XCTAssertEqual(action.kind, .followUp)
        XCTAssertEqual(action.title, "Följ upp med Sara")
        XCTAssertEqual(draft.title, "Följ upp med Sara")
        XCTAssertEqual(draft.eligibleAt.timeIntervalSince(draft.waitingSince), 24 * 60 * 60, accuracy: 1)
        XCTAssertEqual(draft.dueAt, Date(timeIntervalSince1970: 1_742_547_600))
        XCTAssertTrue(action.auditReasons.contains("heuristic:waiting_for_response"))
    }

    func testSmsErrandProducesReminderAction() {
        let detector = makeDetector()

        let decision = detector.decide(for: "Kan du hämta paketet på lördag?")

        guard case .proposed(let action) = decision else {
            return XCTFail("Expected proposed action")
        }
        guard case .reminder(let draft) = action.draft else {
            return XCTFail("Expected reminder draft")
        }

        XCTAssertEqual(action.kind, .reminder)
        XCTAssertEqual(action.title, "Hämta paketet")
        XCTAssertEqual(draft.title, "Hämta paketet")
        XCTAssertNotNil(draft.dueDate)
    }

    func testWriteInCalendarQueryProducesCalendarAction() {
        let detector = makeDetector()

        let decision = detector.decide(for: "Kan du skriva in tvätta imorgon kl 10-13?")

        guard case .proposed(let action) = decision else {
            return XCTFail("Expected proposed action")
        }
        guard case .calendar(let draft) = action.draft else {
            return XCTFail("Expected calendar draft")
        }

        XCTAssertEqual(action.kind, .calendar)
        XCTAssertEqual(action.title, "Tvätta")
        XCTAssertEqual(draft.title, "Tvätta")
        XCTAssertTrue(action.auditReasons.contains("intent:create_request"))
    }

    func testReminderListRequestUsesShortTitleAndListName() {
        let detector = makeDetector()

        let decision = detector.decide(for: "Kan du lägga till tigersåg i påminnelse listan handla?")

        guard case .proposed(let action) = decision else {
            return XCTFail("Expected proposed action")
        }
        guard case .reminder(let draft) = action.draft else {
            return XCTFail("Expected reminder draft")
        }

        XCTAssertEqual(action.kind, .reminder)
        XCTAssertEqual(action.title, "Tigersåg")
        XCTAssertEqual(draft.title, "Tigersåg")
        XCTAssertEqual(draft.listName, "Handla")
    }

    func testStructuredNoteProducesSpecificTitleAndBody() {
        let detector = makeDetector()

        let decision = detector.decide(for: "Portkod till gården: 4582")

        guard case .proposed(let action) = decision else {
            return XCTFail("Expected proposed action")
        }
        guard case .note(let draft) = action.draft else {
            return XCTFail("Expected note draft")
        }

        XCTAssertEqual(action.kind, .note)
        XCTAssertEqual(action.title, "Portkod till gården")
        XCTAssertEqual(draft.title, "Portkod till gården")
        XCTAssertEqual(draft.body, "4582")
    }

    func testExplicitNoteCommandProducesNoteAction() {
        let detector = makeDetector()

        let decision = detector.decide(for: "Skapa ny anteckning: Packlista för resan")

        guard case .proposed(let action) = decision else {
            return XCTFail("Expected proposed action")
        }
        guard case .note(let draft) = action.draft else {
            return XCTFail("Expected note draft")
        }

        XCTAssertEqual(action.kind, .note)
        XCTAssertEqual(action.title, "Packlista för resan")
        XCTAssertEqual(draft.title, "Packlista för resan")
        XCTAssertEqual(draft.body, "Packlista för resan")
    }

    private func makeDetector() -> HeuristicActionSuggestionDetector {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return HeuristicActionSuggestionDetector(
            nowProvider: { Self.fixedNow },
            calendar: calendar
        )
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_742_428_800)
}
