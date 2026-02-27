import XCTest
@testable import Helper

final class QueryDataCollectorsTests: XCTestCase {

    func testMemoryMappingProducesStableIdAndNotesSource() throws {
        let event = RawEvent(
            id: "abc123",
            source: "memory",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            payloadJSON: "{\"kind\":\"note\"}",
            text: "Packa pass till Grekland"
        )

        let mapped = QueryDataFetcher.mapRawEvent(event)

        XCTAssertEqual(mapped.id, "memory:abc123")
        XCTAssertEqual(mapped.source, "notes")
        XCTAssertEqual(mapped.type, .note)
        XCTAssertEqual(mapped.title, "Packa pass till Grekland")
        XCTAssertEqual(mapped.body, "Packa pass till Grekland")
    }

    func testReminderMappingHandlesNilDueDate() {
        let reminder = ReminderItem(title: "Kop mjolk", dueDate: nil)
        let now = Date(timeIntervalSince1970: 1_700_000_100)

        let mapped = QueryDataFetcher.mapReminder(reminder, now: now)

        XCTAssertEqual(mapped.id, "reminder:\(reminder.id)")
        XCTAssertEqual(mapped.source, "reminders")
        XCTAssertEqual(mapped.type, .reminder)
        XCTAssertEqual(mapped.title, "Kop mjolk")
        XCTAssertEqual(mapped.status["is_completed"], AnyCodable(false))
        XCTAssertTrue(mapped.body.contains("Status: pending"))
        XCTAssertNil(mapped.dueAt)
        XCTAssertEqual(mapped.createdAt, now)
        XCTAssertEqual(mapped.updatedAt, now)
    }

    func testCalendarMappingHandlesAllDayAndTimedEvents() {
        let start = Date(timeIntervalSince1970: 1_700_100_000)
        let end = Date(timeIntervalSince1970: 1_700_103_600)

        let allDay = QueryDataFetcher.CalendarSnapshot(
            identifier: "ev-all-day",
            title: "Resdag",
            notes: "Flyg 08:00",
            location: "Arlanda",
            attendees: ["Alva", "Agnes"],
            status: "confirmed",
            startDate: start,
            endDate: end,
            isAllDay: true,
            updatedAt: nil
        )

        let timed = QueryDataFetcher.CalendarSnapshot(
            identifier: "ev-timed",
            title: "Middag",
            notes: nil,
            location: "Plaka",
            attendees: [],
            status: "tentative",
            startDate: start,
            endDate: end,
            isAllDay: false,
            updatedAt: start
        )

        let allDayMapped = QueryDataFetcher.mapCalendarSnapshot(allDay)
        let timedMapped = QueryDataFetcher.mapCalendarSnapshot(timed)

        XCTAssertEqual(allDayMapped.id, "calendar:ev-all-day")
        XCTAssertEqual(allDayMapped.source, "calendar")
        XCTAssertEqual(allDayMapped.type, .event)
        XCTAssertEqual(allDayMapped.startAt, start)
        XCTAssertEqual(allDayMapped.endAt, end)
        XCTAssertEqual(allDayMapped.status["is_all_day"], AnyCodable(true))
        XCTAssertEqual(allDayMapped.status["event_status"], AnyCodable("confirmed"))
        XCTAssertTrue(allDayMapped.body.contains("Deltagare: Alva, Agnes"))
        XCTAssertTrue(allDayMapped.body.contains("Plats: Arlanda"))

        XCTAssertEqual(timedMapped.id, "calendar:ev-timed")
        XCTAssertEqual(timedMapped.status["is_all_day"], AnyCodable(false))
        XCTAssertEqual(timedMapped.status["event_status"], AnyCodable("tentative"))
    }
}
