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

typealias ChatSuggestionActionError = ActionExecutionError
typealias ChatSuggestionReminderHandling = ReminderActionHandling
typealias ChatSuggestionNoteHandling = NoteActionHandling
typealias ChatSuggestionMemorySyncing = ActionMemorySyncing

struct ChatSuggestionCalendarPayload: Equatable {
    let title: String
    let notes: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool

    init(_ payload: CalendarActionPayload) {
        self.title = payload.title
        self.notes = payload.notes
        self.startDate = payload.startDate
        self.endDate = payload.endDate
        self.isAllDay = payload.isAllDay
    }
}

struct ChatSuggestionCalendarPayloadBuilder {
    private let payloadBuilder: CalendarActionPayloadBuilder

    init(calendar: Calendar = .current) {
        self.payloadBuilder = CalendarActionPayloadBuilder(calendar: calendar)
    }

    func build(from draft: ChatSuggestionDraft.CalendarDraft) -> ChatSuggestionCalendarPayload {
        ChatSuggestionCalendarPayload(
            payloadBuilder.build(from: ActionDraft.CalendarDraft(draft))
        )
    }
}

struct ChatSuggestionReminderService: ReminderActionHandling {
    func createReminder(from item: ReminderItem) throws {
        try ReminderSyncManager.shared.createReminder(from: item)
    }
}

struct ChatSuggestionNoteService: NoteActionHandling {
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

extension ICloudMemorySyncCoordinator: ActionMemorySyncing {}

@MainActor
final class ChatSuggestionActionCoordinator: ChatSuggestionActionCoordinating {
    private let actionCoordinator: ActionExecutionCoordinating

    init(actionCoordinator: ActionExecutionCoordinating) {
        self.actionCoordinator = actionCoordinator
    }

    init(
        reminderService: ChatSuggestionReminderHandling,
        noteService: ChatSuggestionNoteHandling,
        memorySyncCoordinator: ChatSuggestionMemorySyncing,
        sourceConnectionStore: SourceConnectionStoring,
        calendar: Calendar = .current
    ) {
        self.actionCoordinator = ActionExecutionCoordinator(
            reminderService: reminderService,
            noteService: noteService,
            memorySyncCoordinator: memorySyncCoordinator,
            sourceConnectionStore: sourceConnectionStore,
            noteSource: "chat_suggestion",
            calendar: calendar
        )
    }

    func makeCalendarEvent(
        from draft: ChatSuggestionDraft.CalendarDraft,
        using store: EKEventStore
    ) throws -> EKEvent {
        try actionCoordinator.makeCalendarEvent(
            from: ActionDraft.CalendarDraft(draft),
            using: store
        )
    }

    func enableCalendarSource() {
        actionCoordinator.enableCalendarSource()
    }

    func createReminder(from draft: ChatSuggestionDraft.ReminderDraft) async throws {
        try await actionCoordinator.createReminder(
            from: ActionDraft.ReminderDraft(draft)
        )
    }

    func createNote(
        from draft: ChatSuggestionDraft.NoteDraft,
        in context: ModelContext
    ) async throws {
        try await actionCoordinator.createNote(
            from: ActionDraft.NoteDraft(draft),
            in: context
        )
    }
}
