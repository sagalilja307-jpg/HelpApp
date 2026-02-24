import Foundation
import SwiftData

private struct ReminderRawPayload: Codable {
    let kind: String
    let reminderId: String
    let title: String
    let dueDate: Date?
    let isCompleted: Bool
}

extension ReminderSyncManager {

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

            let rawId = "reminder:\(item.id)"
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
