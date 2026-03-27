import EventKit
import Foundation
import SwiftData

protocol ReminderActionHandling {
    func createReminder(from item: ReminderItem) throws
}

protocol NoteActionHandling {
    func createNote(
        title: String,
        body: String,
        source: String,
        in context: ModelContext
    ) throws
}

@MainActor
protocol ActionMemorySyncing {
    func syncNow() async -> MemorySyncOutcome
}

struct CalendarActionPayload: Equatable {
    let title: String
    let notes: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
}

struct CalendarActionPayloadBuilder {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func build(from draft: ActionDraft.CalendarDraft) -> CalendarActionPayload {
        CalendarActionPayload(
            title: normalizedTitle(draft.title, fallback: "Ny handelse"),
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
            return calendar.date(byAdding: component, value: 1, to: startDate) ?? startDate
        }
        return endDate
    }
}

struct CalendarActionExecutor {
    private let payloadBuilder: CalendarActionPayloadBuilder

    init(calendar: Calendar = .current) {
        self.payloadBuilder = CalendarActionPayloadBuilder(calendar: calendar)
    }

    func prepareEvent(
        from draft: ActionDraft.CalendarDraft,
        using store: EKEventStore
    ) -> EKEvent {
        let payload = payloadBuilder.build(from: draft)
        let event = EKEvent(eventStore: store)
        event.title = payload.title
        event.notes = payload.notes
        event.startDate = payload.startDate
        event.endDate = payload.endDate
        event.isAllDay = payload.isAllDay
        event.calendar = store.defaultCalendarForNewEvents
        return event
    }
}

struct ReminderActionExecutor {
    private let reminderService: ReminderActionHandling
    private let sourceConnectionStore: SourceConnectionStoring

    init(
        reminderService: ReminderActionHandling,
        sourceConnectionStore: SourceConnectionStoring
    ) {
        self.reminderService = reminderService
        self.sourceConnectionStore = sourceConnectionStore
    }

    func execute(_ draft: ActionDraft.ReminderDraft) throws {
        let title = normalizedTitle(draft.title, fallback: "")
        guard !title.isEmpty else {
            throw ActionExecutionError.emptyReminderTitle
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

    private func normalizedTitle(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
struct NoteActionExecutor {
    private let noteService: NoteActionHandling
    private let memorySyncCoordinator: ActionMemorySyncing
    private let noteSource: String

    init(
        noteService: NoteActionHandling,
        memorySyncCoordinator: ActionMemorySyncing,
        noteSource: String
    ) {
        self.noteService = noteService
        self.memorySyncCoordinator = memorySyncCoordinator
        self.noteSource = noteSource
    }

    func execute(
        _ draft: ActionDraft.NoteDraft,
        in context: ModelContext
    ) async throws {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !body.isEmpty else {
            throw ActionExecutionError.emptyNoteContent
        }

        try noteService.createNote(
            title: title,
            body: body,
            source: noteSource,
            in: context
        )
        _ = await memorySyncCoordinator.syncNow()
    }
}

enum ActionExecutionError: LocalizedError, Equatable {
    case emptyReminderTitle
    case emptyNoteContent
    case followUpUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyReminderTitle:
            return "Paminnelsen behover en titel."
        case .emptyNoteContent:
            return "Anteckningen behover innehall."
        case .followUpUnavailable:
            return "Uppfoljning ar inte tillganglig i det har flodet."
        }
    }
}

@MainActor
protocol ActionExecutionCoordinating {
    func makeCalendarEvent(
        from draft: ActionDraft.CalendarDraft,
        using store: EKEventStore
    ) throws -> EKEvent
    func enableCalendarSource()
    func createReminder(from draft: ActionDraft.ReminderDraft) async throws
    func createNote(
        from draft: ActionDraft.NoteDraft,
        in context: ModelContext
    ) async throws
    func saveFollowUpDraft(
        _ draft: ActionDraft.FollowUpDraft,
        defaultSourceMessageID: String,
        logMessageID: String?,
        reasons: [String]
    ) async throws -> PendingFollowUpSnapshot
    func markFollowUpCompleted(
        from draft: ActionDraft.FollowUpDraft,
        defaultSourceMessageID: String,
        logMessageID: String?,
        reasons: [String]
    ) async throws -> PendingFollowUpSnapshot
}

@MainActor
final class ActionExecutionCoordinator: ActionExecutionCoordinating {
    private let calendarExecutor: CalendarActionExecutor
    private let reminderExecutor: ReminderActionExecutor
    private let noteExecutor: NoteActionExecutor
    private let sourceConnectionStore: SourceConnectionStoring
    private let followUpCoordinator: FollowUpCoordinating?

    init(
        reminderService: ReminderActionHandling,
        noteService: NoteActionHandling,
        memorySyncCoordinator: ActionMemorySyncing,
        sourceConnectionStore: SourceConnectionStoring,
        followUpCoordinator: FollowUpCoordinating? = nil,
        noteSource: String = "action_layer",
        calendar: Calendar = .current
    ) {
        self.calendarExecutor = CalendarActionExecutor(calendar: calendar)
        self.reminderExecutor = ReminderActionExecutor(
            reminderService: reminderService,
            sourceConnectionStore: sourceConnectionStore
        )
        self.noteExecutor = NoteActionExecutor(
            noteService: noteService,
            memorySyncCoordinator: memorySyncCoordinator,
            noteSource: noteSource
        )
        self.sourceConnectionStore = sourceConnectionStore
        self.followUpCoordinator = followUpCoordinator
    }

    func makeCalendarEvent(
        from draft: ActionDraft.CalendarDraft,
        using store: EKEventStore
    ) throws -> EKEvent {
        calendarExecutor.prepareEvent(from: draft, using: store)
    }

    func enableCalendarSource() {
        sourceConnectionStore.setEnabled(true, for: .calendar)
    }

    func createReminder(from draft: ActionDraft.ReminderDraft) async throws {
        try reminderExecutor.execute(draft)
    }

    func createNote(
        from draft: ActionDraft.NoteDraft,
        in context: ModelContext
    ) async throws {
        try await noteExecutor.execute(draft, in: context)
    }

    func saveFollowUpDraft(
        _ draft: ActionDraft.FollowUpDraft,
        defaultSourceMessageID: String,
        logMessageID: String?,
        reasons: [String]
    ) async throws -> PendingFollowUpSnapshot {
        guard let followUpCoordinator else {
            throw ActionExecutionError.followUpUnavailable
        }

        return try await followUpCoordinator.saveFollowUpDraft(
            FollowUpComposerDraft(actionDraft: draft),
            defaultSourceMessageID: defaultSourceMessageID,
            logMessageID: logMessageID,
            reasons: reasons
        )
    }

    func markFollowUpCompleted(
        from draft: ActionDraft.FollowUpDraft,
        defaultSourceMessageID: String,
        logMessageID: String?,
        reasons: [String]
    ) async throws -> PendingFollowUpSnapshot {
        guard let followUpCoordinator else {
            throw ActionExecutionError.followUpUnavailable
        }

        return try await followUpCoordinator.markFollowUpCompleted(
            from: FollowUpComposerDraft(actionDraft: draft),
            defaultSourceMessageID: defaultSourceMessageID,
            logMessageID: logMessageID,
            reasons: reasons
        )
    }
}

private extension FollowUpComposerDraft {
    init(actionDraft: ActionDraft.FollowUpDraft) {
        self.init(
            sourceMessageID: nil,
            clusterID: actionDraft.clusterID,
            title: actionDraft.title,
            contextText: actionDraft.contextText,
            draftText: actionDraft.draftText,
            waitingSince: actionDraft.waitingSince,
            eligibleAt: actionDraft.eligibleAt,
            dueAt: actionDraft.dueAt
        )
    }
}
