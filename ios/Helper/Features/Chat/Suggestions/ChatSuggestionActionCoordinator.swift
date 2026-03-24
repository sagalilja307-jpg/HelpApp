import EventKit
import Foundation
import SwiftData

protocol ChatSuggestionActionCoordinating {
    func makeCalendarEvent(
        from draft: ChatSuggestionDraft.CalendarDraft,
        using store: EKEventStore
    ) throws -> EKEvent
    func enableCalendarSource()
    func createReminder(from draft: ChatSuggestionDraft.ReminderDraft) async throws
    func createNote(
        from draft: ChatSuggestionDraft.NoteDraft,
        in context: ModelContext
    ) async throws
}

struct ChatSuggestionCalendarPayload: Equatable {
    let title: String
    let notes: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
}

struct ChatSuggestionCalendarPayloadBuilder {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func build(from draft: ChatSuggestionDraft.CalendarDraft) -> ChatSuggestionCalendarPayload {
        ChatSuggestionCalendarPayload(
            title: normalizedTitle(draft.title, fallback: "Ny händelse"),
            notes: trimmedOrNil(draft.notes),
            startDate: draft.startDate,
            endDate: normalizedCalendarEndDate(
                startDate: draft.startDate,
                endDate: draft.endDate,
                isAllDay: draft.isAllDay
            ),
            isAllDay: draft.isAllDay
        )
    }
}

enum ChatSuggestionActionError: LocalizedError, Equatable {
    case emptyReminderTitle
    case emptyNoteContent

    var errorDescription: String? {
        switch self {
        case .emptyReminderTitle:
            return "Påminnelsen behöver en titel."
        case .emptyNoteContent:
            return "Anteckningen behöver innehåll."
        }
    }
}

protocol ChatSuggestionReminderHandling {
    func createReminder(from item: ReminderItem) throws
}

protocol ChatSuggestionNoteHandling {
    func createNote(
        title: String,
        body: String,
        source: String,
        in context: ModelContext
    ) throws
}

@MainActor
protocol ChatSuggestionMemorySyncing {
    func syncNow() async -> MemorySyncOutcome
}

struct ChatSuggestionReminderService: ChatSuggestionReminderHandling {
    func createReminder(from item: ReminderItem) throws {
        try ReminderSyncManager.shared.createReminder(from: item)
    }
}

struct ChatSuggestionNoteService: ChatSuggestionNoteHandling {
    func createNote(
        title: String,
        body: String,
        source: String,
        in context: ModelContext
    ) throws {
        _ = try NotesStoreService().createNote(
            title: title,
            body: body,
            source: source,
            in: context
        )
    }
}

extension ICloudMemorySyncCoordinator: ChatSuggestionMemorySyncing {}

@MainActor
final class ChatSuggestionActionCoordinator: ChatSuggestionActionCoordinating {
    private let reminderService: ChatSuggestionReminderHandling
    private let noteService: ChatSuggestionNoteHandling
    private let memorySyncCoordinator: ChatSuggestionMemorySyncing
    private let sourceConnectionStore: SourceConnectionStoring
    private let calendarPayloadBuilder: ChatSuggestionCalendarPayloadBuilder

    init(
        reminderService: ChatSuggestionReminderHandling,
        noteService: ChatSuggestionNoteHandling,
        memorySyncCoordinator: ChatSuggestionMemorySyncing,
        sourceConnectionStore: SourceConnectionStoring,
        calendar: Calendar = .current
    ) {
        self.reminderService = reminderService
        self.noteService = noteService
        self.memorySyncCoordinator = memorySyncCoordinator
        self.sourceConnectionStore = sourceConnectionStore
        self.calendarPayloadBuilder = ChatSuggestionCalendarPayloadBuilder(calendar: calendar)
    }

    func makeCalendarEvent(
        from draft: ChatSuggestionDraft.CalendarDraft,
        using store: EKEventStore
    ) throws -> EKEvent {
        let payload = calendarPayloadBuilder.build(from: draft)
        let event = EKEvent(eventStore: store)

        event.title = payload.title
        event.notes = payload.notes
        event.startDate = payload.startDate
        event.endDate = payload.endDate
        event.isAllDay = payload.isAllDay
        event.calendar = store.defaultCalendarForNewEvents

        return event
    }

    func enableCalendarSource() {
        sourceConnectionStore.setEnabled(true, for: .calendar)
    }

    func createReminder(from draft: ChatSuggestionDraft.ReminderDraft) async throws {
        let title = normalizedTitle(draft.title, fallback: "")
        guard !title.isEmpty else {
            throw ChatSuggestionActionError.emptyReminderTitle
        }

        let reminder = ReminderItem(
            title: title,
            dueDate: draft.dueDate,
            notes: trimmedOrNil(draft.notes),
            location: trimmedOrNil(draft.location),
            priority: draft.priority?.eventKitValue
        )

        try reminderService.createReminder(from: reminder)
        sourceConnectionStore.setEnabled(true, for: .reminders)
    }

    func createNote(
        from draft: ChatSuggestionDraft.NoteDraft,
        in context: ModelContext
    ) async throws {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !body.isEmpty else {
            throw ChatSuggestionActionError.emptyNoteContent
        }

        try noteService.createNote(
            title: title,
            body: body,
            source: "chat_suggestion",
            in: context
        )
        _ = await memorySyncCoordinator.syncNow()
    }
}

private extension ChatSuggestionActionCoordinator {
    func normalizedTitle(_ value: String, fallback: String) -> String {
        calendarPayloadBuilder.normalizedTitle(value, fallback: fallback)
    }

    func trimmedOrNil(_ value: String?) -> String? {
        calendarPayloadBuilder.trimmedOrNil(value)
    }
}

private extension ChatSuggestionCalendarPayloadBuilder {
    func normalizedTitle(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func normalizedCalendarEndDate(
        startDate: Date,
        endDate: Date,
        isAllDay: Bool
    ) -> Date {
        guard endDate > startDate else {
            let component: Calendar.Component = isAllDay ? .day : .hour
            let value = isAllDay ? 1 : 1
            return calendar.date(byAdding: component, value: value, to: startDate) ?? startDate
        }
        return endDate
    }
}
