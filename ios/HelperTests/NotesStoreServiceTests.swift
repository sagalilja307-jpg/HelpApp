import XCTest
import SwiftData
@testable import Helper

@MainActor
final class NotesStoreServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var service: NotesStoreService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: UserNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        service = NotesStoreService(context: ModelContext(container))
    }

    override func tearDownWithError() throws {
        service = nil
        container = nil
        try super.tearDownWithError()
    }

    private func makeService() throws -> NotesStoreService {
        try XCTUnwrap(service)
    }

    func testCreateListAndExportNotes() throws {
        let service = try makeService()

        _ = try service.createNote(title: "Grekland", body: "Boka hotell", source: "user")
        let notes = try service.listNotes()

        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "Grekland")

        let exported = try service.exportUnifiedItems(in: nil)
        XCTAssertEqual(exported.count, 1)
        XCTAssertEqual(exported.first?.source, "notes")
        XCTAssertEqual(exported.first?.type, .note)
    }

    func testUpsertImportedNoteDeduplicatesByExternalRef() throws {
        let service = try makeService()

        _ = try service.upsertImportedNote(
            title: "Delad text",
            body: "Version 1",
            source: "share_text",
            externalRef: "ext-1"
        )

        _ = try service.upsertImportedNote(
            title: "Delad text",
            body: "Version 2",
            source: "share_text",
            externalRef: "ext-1"
        )

        let notes = try service.listNotes()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.body, "Version 2")
    }
}
