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
        XCTAssertEqual(draft.title, "Följ upp med Sara")
        XCTAssertEqual(draft.eligibleAt.timeIntervalSince(draft.waitingSince), 24 * 60 * 60, accuracy: 1)
        XCTAssertEqual(draft.dueAt, Date(timeIntervalSince1970: 1_742_547_600))
        XCTAssertTrue(action.auditReasons.contains("heuristic:waiting_for_response"))
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
