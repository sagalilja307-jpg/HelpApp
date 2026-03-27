
import Foundation
import EventKit

struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let dueDate: Date?
    let isCompleted: Bool
    let notes: String?
    let location: String?
    let priority: Int?
    let listName: String?

    init(from ekReminder: EKReminder) {
        self.id = ekReminder.calendarItemIdentifier
        self.title = ekReminder.title ?? ""
        self.dueDate = ekReminder.dueDateComponents?.date
        self.isCompleted = ekReminder.isCompleted
        self.notes = ekReminder.notes
        self.location = ekReminder.location
        self.priority = ekReminder.priority
        self.listName = ekReminder.calendar.title
    }

    init(
        title: String,
        dueDate: Date?,
        notes: String? = nil,
        location: String? = nil,
        priority: Int? = nil,
        listName: String? = nil
    ) {
        self.id = UUID().uuidString
        self.title = title
        self.dueDate = dueDate
        self.isCompleted = false
        self.notes = notes
        self.location = location
        self.priority = priority
        self.listName = listName
    }
}
