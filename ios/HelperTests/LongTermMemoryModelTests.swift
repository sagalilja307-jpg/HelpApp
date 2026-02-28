import XCTest
import SwiftData
@testable import Helper

@MainActor
final class LongTermMemoryModelTests: XCTestCase {

    func testCanInsertPendingJobInMemoryStore() throws {
        let container = try ModelContainer(
            for: LongTermMemoryPendingJob.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let job = LongTermMemoryPendingJob(
            text: "hello",
            language: "sv",
            now: now
        )
        context.insert(job)
        try context.save()

        let jobs = try context.fetch(FetchDescriptor<LongTermMemoryPendingJob>())
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs[0].status, .pending)
    }

    func testCanInsertLongTermMemoryItemInMemoryStore() throws {
        let container = try ModelContainer(
            for: LongTermMemoryItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let item = LongTermMemoryItem(
            originalText: "raw",
            cleanText: "clean",
            cognitiveType: "insight",
            domain: "learning",
            actionState: "observe",
            timeRelation: "present",
            tags: ["a", "b"],
            embedding: [0.1, -0.2]
        )
        context.insert(item)
        try context.save()

        let items = try context.fetch(FetchDescriptor<LongTermMemoryItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].cognitiveType, "insight")
        XCTAssertEqual(items[0].domain, "learning")
        XCTAssertEqual(items[0].actionState, "observe")
        XCTAssertEqual(items[0].timeRelation, "present")
        XCTAssertEqual(items[0].tags, ["a", "b"])
        XCTAssertEqual(items[0].embedding, [0.1, -0.2])
    }
}
