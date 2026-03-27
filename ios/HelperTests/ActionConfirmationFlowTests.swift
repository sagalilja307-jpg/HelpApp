import XCTest
@testable import Helper

final class ActionConfirmationFlowTests: XCTestCase {

    func testDismissMarksAwaitingApprovalAsDismissed() {
        let state = ActionConfirmationFlow.transition(
            from: .awaitingApproval,
            event: .dismiss
        )

        XCTAssertEqual(state, .dismissed)
    }

    func testRestoreApprovalKeepsDismissedStateTerminal() {
        let state = ActionConfirmationFlow.transition(
            from: .dismissed,
            event: .restoreApproval
        )

        XCTAssertEqual(state, .dismissed)
    }

    func testRestoreApprovalMovesFailedStateBackToAwaitingApproval() {
        let state = ActionConfirmationFlow.transition(
            from: .failed("Misslyckades"),
            event: .restoreApproval
        )

        XCTAssertEqual(state, .awaitingApproval)
    }
}
