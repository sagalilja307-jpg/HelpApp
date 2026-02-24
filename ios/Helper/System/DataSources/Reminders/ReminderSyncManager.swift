import EventKit
import Foundation
import SwiftData


final class ReminderSyncManager {

    static let shared = ReminderSyncManager()

    private let eventStore = EKEventStore()

    private init() {}

    // MARK: - Permissions

    func requestAccess() async throws {
        let op = "RemindersRequestAccess"
        DataSourceDebug.start(op)
        do {
            if #available(iOS 17.0, *) {
                try await eventStore.requestFullAccessToReminders()
            } else {
                // Fallback for iOS versions prior to 17
                try await eventStore.requestAccess(to: .reminder)
            }
            DataSourceDebug.success(op)
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }

    // MARK: - Read

    func fetchActiveReminders() async throws -> [ReminderItem] {
        let op = "RemindersFetchActive"
        DataSourceDebug.start(op)
        do {
            let calendars = eventStore.calendars(for: .reminder)

            let reminders = try await withCheckedThrowingContinuation { continuation in
                let predicate = eventStore.predicateForIncompleteReminders(
                    withDueDateStarting: nil,
                    ending: nil,
                    calendars: calendars
                )

                eventStore.fetchReminders(matching: predicate) { reminders in
                    let items = reminders?.map { ReminderItem(from: $0) } ?? []
                    continuation.resume(returning: items)
                }
            }
            DataSourceDebug.success(op, count: reminders.count)
            return reminders
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }

    // MARK: - Write

    func createReminder(from item: ReminderItem) throws {
        let op = "RemindersCreate"
        DataSourceDebug.start(op)
        do {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = item.title
            reminder.calendar = eventStore.defaultCalendarForNewReminders()

            if let dueDate = item.dueDate {
                reminder.dueDateComponents = DateService.shared.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: dueDate
                )
            }

            try eventStore.save(reminder, commit: true)
            DataSourceDebug.success(op, count: 1)
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }

    // MARK: - Utility

    func reminderExists(with title: String) async throws -> Bool {
        let reminders = try await fetchActiveReminders()
        return reminders.contains { $0.title == title }
    }
}


// Lägg dessa under klassen (eller längst ner i filen)
private struct ReminderRawPayload: Codable {
    let kind: String            // "reminder"
    let reminderId: String      // EK identifier
    let title: String
    let dueDate: Date?
    let isCompleted: Bool
}

extension ReminderSyncManager {

    /// Hämtar aktiva påminnelser och speglar dem till RawEvent i MemoryService.
    /// Returnerar antal items som skrevs/uppdaterades.
    func syncActiveRemindersToMemory(
        memory: MemoryService,
        in context: ModelContext
    ) async throws -> Int {

        let reminders = try await fetchActiveReminders()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        for item in reminders {
            let payload = ReminderRawPayload(
                kind: "reminder",
                reminderId: item.id,
                title: item.title,
                dueDate: item.dueDate,
                isCompleted: item.isCompleted
            )

            let data = try encoder.encode(payload)
            let payloadJSON = String(data: data, encoding: .utf8) ?? "{}"

            // Stabilt id i ditt minne (samma reminder -> samma raw_event id)
            let rawId = "reminder:\(item.id)"

            // timestamp: använd dueDate om den finns, annars "nu"
            let ts = item.dueDate ?? DateService.shared.now()

            try memory.putRawEvent(
                actor: .system,
                id: rawId,
                source: "reminders",
                timestamp: ts,
                payloadJSON: payloadJSON,
                in: context
            )
        }

        return reminders.count
    }
}
