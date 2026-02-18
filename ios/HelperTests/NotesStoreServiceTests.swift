import XCTest
import SwiftData
@testable import Helper

@MainActor
final class NotesStoreServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: NotesStoreService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: UserNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        service = NotesStoreService()
    }

    override func tearDownWithError() throws {
        service = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    private func makeService() throws -> NotesStoreService {
        try XCTUnwrap(service)
    }

    private func makeContext() throws -> ModelContext {
        try XCTUnwrap(context)
    }

    func testCreateListAndExportNotes() throws {
        let service = try makeService()
        let context = try makeContext()

        _ = try service.createNote(title: "Grekland", body: "Boka hotell", source: "user", in: context)
        let notes = try service.listNotes(in: context)

        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "Grekland")

        let exported = try service.exportUnifiedItems(in: nil, context: context)
        XCTAssertEqual(exported.count, 1)
        XCTAssertEqual(exported.first?.source, "notes")
        XCTAssertEqual(exported.first?.type, .note)
    }

    func testUpsertImportedNoteDeduplicatesByExternalRef() throws {
        let service = try makeService()
        let context = try makeContext()

        _ = try service.upsertImportedNote(
            title: "Delad text",
            body: "Version 1",
            source: "share_text",
            externalRef: "ext-1",
            in: context
        )

        _ = try service.upsertImportedNote(
            title: "Delad text",
            body: "Version 2",
            source: "share_text",
            externalRef: "ext-1",
            in: context
        )

        let notes = try service.listNotes(in: context)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.body, "Version 2")
    }
}
