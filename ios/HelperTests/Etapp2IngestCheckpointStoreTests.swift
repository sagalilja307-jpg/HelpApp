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
        let store = Etapp2IngestCheckpointStore(context: context)

        XCTAssertNil(try store.lastCheckpoint(for: .contacts))

        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)

        try store.updateCheckpoint(for: .contacts, at: first)
        XCTAssertEqual(try store.lastCheckpoint(for: .contacts), first)

        try store.updateCheckpoint(for: .contacts, at: second)
        XCTAssertEqual(try store.lastCheckpoint(for: .contacts), second)
    }

    func testNonStage2SourceReturnsNilAndNoopUpdate() throws {
        let container = try ModelContainer(
            for: Etapp2IngestCheckpoint.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = Etapp2IngestCheckpointStore(context: context)

        XCTAssertNil(try store.lastCheckpoint(for: .memory))
        XCTAssertNoThrow(try store.updateCheckpoint(for: .memory, at: Date()))
        XCTAssertNil(try store.lastCheckpoint(for: .memory))
    }
}
