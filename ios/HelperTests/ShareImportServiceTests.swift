import XCTest
import SwiftData
@testable import Helper

@MainActor
final class ShareImportServiceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: UserNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func makeNotesStore() throws -> NotesStoreService {
        let container = try XCTUnwrap(container)
        return NotesStoreService(context: ModelContext(container))
    }

    func testImportSharedItemsCreatesNotesAndClearsPayload() throws {
        let suiteName = "test.share.import.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        let notesStore = try makeNotesStore()
        let service = ShareImportService(notesStore: notesStore, defaults: defaults)

        let envelope = SharedItemsEnvelope(
            version: .v1,
            items: [
                SharedItemPayload(
                    id: "item-1",
                    kind: .text,
                    value: "Packa pass",
                    source: "share_text",
                    createdAt: Date()
                ),
                SharedItemPayload(
                    id: "item-2",
                    kind: .url,
                    value: "https://example.com",
                    source: "share_url",
                    createdAt: Date()
                )
            ],
            createdAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode(envelope), forKey: AppIntegrationConfig.sharedItemsKey)

        let count = try service.importPendingSharedItems()
        XCTAssertEqual(count, 2)

        let notes = try notesStore.listNotes()
        XCTAssertEqual(notes.count, 2)
        XCTAssertNil(defaults.data(forKey: AppIntegrationConfig.sharedItemsKey))
    }
}
