import XCTest
@testable import Helper

final class ReminderSyncManagerTests: XCTestCase {
    func testBestMatchingReminderListNameFindsCaseInsensitiveMatch() {
        let match = ReminderSyncManager.bestMatchingReminderListName(
            for: "handla",
            availableListNames: ["Privat", "Handla", "Jobb"]
        )

        XCTAssertEqual(match, "Handla")
    }

    func testBestMatchingReminderListNameFallsBackToContainingMatch() {
        let match = ReminderSyncManager.bestMatchingReminderListName(
            for: "handla",
            availableListNames: ["Handla hemma", "Jobb"]
        )

        XCTAssertEqual(match, "Handla hemma")
    }
}
