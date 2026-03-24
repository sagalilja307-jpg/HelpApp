import SwiftData
import XCTest
@testable import Helper

@MainActor
final class ChatSuggestionActionCoordinatorTests: XCTestCase {
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
        let coordinator = ChatSuggestionActionCoordinator(
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
        let coordinator = ChatSuggestionActionCoordinator(
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
        XCTAssertEqual(noteService.createdNotes.first?.source, "chat_suggestion")
        XCTAssertEqual(memorySyncCoordinator.syncCount, 1)
    }

    func testMakeCalendarPayloadNormalizesValues() {
        let sourceStore = InMemorySourceConnectionStore()
        let payloadBuilder = ChatSuggestionCalendarPayloadBuilder(
            calendar: Calendar(identifier: .gregorian)
        )
        let startDate = Date(timeIntervalSince1970: 1_742_515_200)
        let invalidEndDate = startDate

        let payload = payloadBuilder.build(
            from: .init(
                title: "  Möte med Sara  ",
                notes: "  Ta med agenda  ",
                startDate: startDate,
                endDate: invalidEndDate,
                isAllDay: false
            )
        )

        XCTAssertEqual(payload.title, "Möte med Sara")
        XCTAssertEqual(payload.notes, "Ta med agenda")
        XCTAssertEqual(payload.startDate, startDate)
        XCTAssertEqual(payload.endDate, startDate.addingTimeInterval(3600))
        XCTAssertFalse(payload.isAllDay)
        XCTAssertFalse(sourceStore.isEnabled(.calendar))
    }

    func testCreateReminderRejectsEmptyTitle() async {
        let coordinator = ChatSuggestionActionCoordinator(
            reminderService: RecordingReminderService(),
            noteService: RecordingNoteService(),
            memorySyncCoordinator: RecordingMemorySyncCoordinator(),
            sourceConnectionStore: InMemorySourceConnectionStore()
        )

        do {
            try await coordinator.createReminder(
                from: .init(
                    title: "   ",
                    dueDate: nil,
                    notes: "",
                    location: nil,
                    priority: nil
                )
            )
            XCTFail("Expected empty title to fail")
        } catch let error as ChatSuggestionActionError {
            XCTAssertEqual(error, .emptyReminderTitle)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeModelContext() throws -> ModelContext {
        XCTAssertNotNil(container)
        return ModelContext(container)
    }
}

private final class RecordingReminderService: ChatSuggestionReminderHandling {
    private(set) var createdItems: [ReminderItem] = []

    func createReminder(from item: ReminderItem) throws {
        createdItems.append(item)
    }
}

private final class RecordingNoteService: ChatSuggestionNoteHandling {
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
private final class RecordingMemorySyncCoordinator: ChatSuggestionMemorySyncing {
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
