import SwiftData
import XCTest
@testable import Helper

@MainActor
final class ActionExecutionCoordinatorTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([UserNote.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    func testCreateReminderMapsDraftAndEnablesRemindersSource() async throws {
        let reminderService = RecordingReminderService()
        let sourceStore = InMemorySourceConnectionStore()
        let coordinator = ActionExecutionCoordinator(
            reminderService: reminderService,
            noteService: RecordingNoteService(),
            memorySyncCoordinator: RecordingMemorySyncCoordinator(),
            sourceConnectionStore: sourceStore
        )

        try await coordinator.createReminder(
            from: .init(
                title: "  Ring tandlakaren  ",
                dueDate: Date(timeIntervalSince1970: 1_742_515_200),
                notes: "  Viktigt  ",
                location: "  Slussen  ",
                priority: .high
            )
        )

        XCTAssertEqual(reminderService.createdItems.count, 1)
        XCTAssertEqual(reminderService.createdItems.first?.title, "Ring tandlakaren")
        XCTAssertEqual(reminderService.createdItems.first?.notes, "Viktigt")
        XCTAssertEqual(reminderService.createdItems.first?.location, "Slussen")
        XCTAssertEqual(reminderService.createdItems.first?.priority, 1)
        XCTAssertTrue(sourceStore.isEnabled(.reminders))
    }

    func testCreateNotePersistsAndTriggersSync() async throws {
        let noteService = RecordingNoteService()
        let memorySyncCoordinator = RecordingMemorySyncCoordinator()
        let coordinator = ActionExecutionCoordinator(
            reminderService: RecordingReminderService(),
            noteService: noteService,
            memorySyncCoordinator: memorySyncCoordinator,
            sourceConnectionStore: InMemorySourceConnectionStore()
        )

        try await coordinator.createNote(
            from: .init(
                title: "  Portkod  ",
                body: "  4582  "
            ),
            in: makeModelContext()
        )

        XCTAssertEqual(noteService.createdNotes.count, 1)
        XCTAssertEqual(noteService.createdNotes.first?.title, "Portkod")
        XCTAssertEqual(noteService.createdNotes.first?.body, "4582")
        XCTAssertEqual(noteService.createdNotes.first?.source, "action_layer")
        XCTAssertEqual(memorySyncCoordinator.syncCount, 1)
    }

    func testSaveFollowUpDraftDelegatesToFollowUpCoordinator() async throws {
        let followUpCoordinator = RecordingFollowUpCoordinator()
        let coordinator = ActionExecutionCoordinator(
            reminderService: RecordingReminderService(),
            noteService: RecordingNoteService(),
            memorySyncCoordinator: RecordingMemorySyncCoordinator(),
            sourceConnectionStore: InMemorySourceConnectionStore(),
            followUpCoordinator: followUpCoordinator
        )
        let waitingSince = Date(timeIntervalSince1970: 1_742_428_800)

        let saved = try await coordinator.saveFollowUpDraft(
            .init(
                title: "Folj upp med Sara",
                draftText: "Hej Sara!",
                contextText: "Vantar pa svar fran Sara.",
                waitingSince: waitingSince,
                eligibleAt: waitingSince.addingTimeInterval(24 * 60 * 60),
                dueAt: Date(timeIntervalSince1970: 1_742_547_600),
                clusterID: "cluster-1"
            ),
            defaultSourceMessageID: "assistant-message",
            logMessageID: "assistant-message",
            reasons: ["trigger:user_text"]
        )

        XCTAssertEqual(saved.id, "follow-up-1")
        XCTAssertEqual(followUpCoordinator.savedDrafts.count, 1)
        XCTAssertEqual(followUpCoordinator.savedDrafts.first?.title, "Folj upp med Sara")
        XCTAssertEqual(followUpCoordinator.savedDrafts.first?.clusterID, "cluster-1")
    }

    private func makeModelContext() throws -> ModelContext {
        XCTAssertNotNil(container)
        return ModelContext(container)
    }
}

private final class RecordingReminderService: ReminderActionHandling {
    private(set) var createdItems: [ReminderItem] = []

    func createReminder(from item: ReminderItem) throws {
        createdItems.append(item)
    }
}

private final class RecordingNoteService: NoteActionHandling {
    struct CreatedNote {
        let title: String
        let body: String
        let source: String
    }

    private(set) var createdNotes: [CreatedNote] = []

    func createNote(
        title: String,
        body: String,
        source: String,
        in context: ModelContext
    ) throws {
        _ = context
        createdNotes.append(
            CreatedNote(
                title: title,
                body: body,
                source: source
            )
        )
    }
}

@MainActor
private final class RecordingMemorySyncCoordinator: ActionMemorySyncing {
    private(set) var syncCount = 0

    func syncNow() async -> MemorySyncOutcome {
        syncCount += 1
        return MemorySyncOutcome(
            status: .synced,
            message: "OK",
            mergedNotes: 0,
            mergedLongTermItems: 0
        )
    }
}

@MainActor
private final class RecordingFollowUpCoordinator: FollowUpCoordinating {
    private(set) var savedDrafts: [FollowUpComposerDraft] = []

    func saveFollowUpDraft(
        _ draft: FollowUpComposerDraft,
        defaultSourceMessageID: String,
        logMessageID: String?,
        reasons: [String]
    ) async throws -> PendingFollowUpSnapshot {
        _ = (defaultSourceMessageID, logMessageID, reasons)
        savedDrafts.append(draft)
        return PendingFollowUpSnapshot(
            id: "follow-up-1",
            sourceMessageID: "assistant-message",
            clusterID: draft.clusterID,
            title: draft.title,
            contextText: draft.contextText,
            draftText: draft.draftText,
            createdAt: draft.waitingSince,
            waitingSince: draft.waitingSince,
            eligibleAt: draft.eligibleAt,
            dueAt: draft.dueAt,
            state: .scheduled,
            lastNotificationAt: nil,
            snoozedUntil: nil,
            completedAt: nil
        )
    }

    func markFollowUpCompleted(
        from draft: FollowUpComposerDraft,
        defaultSourceMessageID: String,
        logMessageID: String?,
        reasons: [String]
    ) async throws -> PendingFollowUpSnapshot {
        _ = (draft, defaultSourceMessageID, logMessageID, reasons)
        return PendingFollowUpSnapshot(
            id: "follow-up-1",
            sourceMessageID: "assistant-message",
            clusterID: nil,
            title: "Folj upp",
            contextText: "",
            draftText: "",
            createdAt: Date(timeIntervalSince1970: 0),
            waitingSince: Date(timeIntervalSince1970: 0),
            eligibleAt: Date(timeIntervalSince1970: 0),
            dueAt: Date(timeIntervalSince1970: 0),
            state: .completed,
            lastNotificationAt: nil,
            snoozedUntil: nil,
            completedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func snoozeFollowUp(id: String) async throws -> PendingFollowUpSnapshot? {
        _ = id
        return nil
    }

    func cancelFollowUp(id: String) async throws -> PendingFollowUpSnapshot? {
        _ = id
        return nil
    }

    func loadActiveFollowUps() async -> [PendingFollowUpSnapshot] {
        []
    }
}

private final class InMemorySourceConnectionStore: SourceConnectionStoring, @unchecked Sendable {
    private var enabledSources: Set<String> = []
    private var importedFiles = false

    func isEnabled(_ source: QuerySource) -> Bool {
        enabledSources.contains(source.rawValue)
    }

    func setEnabled(_ enabled: Bool, for source: QuerySource) {
        if enabled {
            enabledSources.insert(source.rawValue)
        } else {
            enabledSources.remove(source.rawValue)
        }
    }

    func isOCREnabled(for source: QuerySource) -> Bool {
        _ = source
        return false
    }

    func setOCREnabled(_ enabled: Bool, for source: QuerySource) {
        _ = (enabled, source)
    }

    func hasImportedFiles() -> Bool {
        importedFiles
    }

    func setHasImportedFiles(_ hasImportedFiles: Bool) {
        importedFiles = hasImportedFiles
    }
}
