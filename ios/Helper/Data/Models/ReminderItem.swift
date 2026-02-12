
import Foundation
import EventKit

struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let dueDate: Date?
    let isCompleted: Bool

    init(from ekReminder: EKReminder) {
        self.id = ekReminder.calendarItemIdentifier
        self.title = ekReminder.title ?? ""
        self.dueDate = ekReminder.dueDateComponents?.date
        self.isCompleted = ekReminder.isCompleted
    }

    init(title: String, dueDate: Date?) {
        self.id = UUID().uuidString
        self.title = title
        self.dueDate = dueDate
        self.isCompleted = false
    }
}
