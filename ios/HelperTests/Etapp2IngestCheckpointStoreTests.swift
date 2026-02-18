import XCTest
import SwiftData
@testable import Helper

@MainActor
final class Etapp2IngestCheckpointStoreTests: XCTestCase {

    func testCheckpointUpdatesAndReadsStage2Sources() throws {
        let container = try ModelContainer(
            for: Etapp2IngestCheckpoint.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = Etapp2IngestCheckpointStore()

        XCTAssertNil(try store.lastCheckpoint(for: .contacts, in: context))

        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)

        try store.updateCheckpoint(for: .contacts, at: first, in: context)
        XCTAssertEqual(try store.lastCheckpoint(for: .contacts, in: context), first)

        try store.updateCheckpoint(for: .contacts, at: second, in: context)
        XCTAssertEqual(try store.lastCheckpoint(for: .contacts, in: context), second)
    }

    func testNonStage2SourceReturnsNilAndNoopUpdate() throws {
        let container = try ModelContainer(
            for: Etapp2IngestCheckpoint.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = Etapp2IngestCheckpointStore()

        XCTAssertNil(try store.lastCheckpoint(for: .memory, in: context))
        XCTAssertNoThrow(try store.updateCheckpoint(for: .memory, at: Date(), in: context))
        XCTAssertNil(try store.lastCheckpoint(for: .memory, in: context))
    }
}
