import XCTest
import SwiftData
@testable import Helper

@MainActor
final class LongTermMemorySaveCoordinatorTests: XCTestCase {

    private final class MutableClock {
        var now: Date

        init(now: Date) {
            self.now = now
        }
    }

    private var container: ModelContainer!
    private var clock: MutableClock!
    private var api: MockMemoryProcessingAPI!
    private var coordinator: LongTermMemorySaveCoordinator!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([
            LongTermMemoryItem.self,
            LongTermMemoryPendingJob.self,
        ])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        clock = MutableClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        api = MockMemoryProcessingAPI()
        coordinator = LongTermMemorySaveCoordinator(
            container: container,
            memoryProcessingAPI: api,
            nowProvider: {
                self.clock.now
            }
        )
    }

    override func tearDownWithError() throws {
        coordinator = nil
        api = nil
        clock = nil
        container = nil
        try super.tearDownWithError()
    }

    func testSaveSuccessCreatesLongTermItemAndClearsQueue() async throws {
        api.results = [
            .success(
                ProcessMemoryResponseDTO(
                    cleanText: "Strukturerad text",
                    cognitiveType: "decision",
                    domain: "relationship",
                    actionState: "todo",
                    timeRelation: "future",
                    tags: ["product", "memory"],
                    embedding: [0.1, 0.2]
                )
            )
        ]

        let outcome = await coordinator.save(text: "  Originaltext  ", language: "sv")
        XCTAssertEqual(outcome, .saved)

        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<LongTermMemoryItem>())
        let jobs = try context.fetch(FetchDescriptor<LongTermMemoryPendingJob>())

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.originalText, "Originaltext")
        XCTAssertEqual(items.first?.cleanText, "Strukturerad text")
        XCTAssertEqual(items.first?.cognitiveType, "decision")
        XCTAssertEqual(items.first?.domain, "relationship")
        XCTAssertEqual(items.first?.actionState, "todo")
        XCTAssertEqual(items.first?.timeRelation, "future")
        XCTAssertEqual(items.first?.tags, ["product", "memory"])
        XCTAssertEqual(items.first?.embedding, [0.1, 0.2])
        XCTAssertTrue(jobs.isEmpty)
    }

    func testSaveQueuesRetryOnBackendFailure() async throws {
        api.results = [
            .failure(MemoryProcessingAPIError.serverError(503, "Unavailable"))
        ]

        let outcome = await coordinator.save(text: "Retry me", language: "sv")
        XCTAssertEqual(outcome, .queued)

        let context = ModelContext(container)
        let jobs = try context.fetch(FetchDescriptor<LongTermMemoryPendingJob>())
        let items = try context.fetch(FetchDescriptor<LongTermMemoryItem>())

        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs[0].status, .pending)
        XCTAssertEqual(jobs[0].attemptCount, 1)
        XCTAssertGreaterThan(jobs[0].nextRetryAt, clock.now)
        XCTAssertTrue(items.isEmpty)
    }

    func testSaveMarksFailedOnClientValidationFailure() async throws {
        api.results = [
            .failure(MemoryProcessingAPIError.serverError(400, "Bad request"))
        ]

        let outcome = await coordinator.save(text: "Bad input", language: "sv")
        switch outcome {
        case .failed:
            break
        default:
            XCTFail("Expected failed outcome, got \(outcome)")
        }

        let context = ModelContext(container)
        let jobs = try context.fetch(FetchDescriptor<LongTermMemoryPendingJob>())
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs[0].status, .failed)
    }

    func testUnknownSuggestedTypeMapsToOther() {
        let item = LongTermMemoryItem(
            originalText: "raw",
            cleanText: "clean",
            suggestedType: "SomethingUnexpected",
            tags: [],
            embedding: [0.01]
        )

        XCTAssertEqual(item.normalizedType, .other)
    }

    func testLoadAllItemsReturnsNewestFirstAndSupportsLimit() throws {
        let context = ModelContext(container)

        let older = LongTermMemoryItem(
            originalText: "raw-old",
            cleanText: "old",
            suggestedType: "Insight",
            tags: [],
            embedding: [0.1]
        )
        older.createdAt = Date(timeIntervalSince1970: 10)

        let newer = LongTermMemoryItem(
            originalText: "raw-new",
            cleanText: "new",
            suggestedType: "Insight",
            tags: [],
            embedding: [0.2]
        )
        newer.createdAt = Date(timeIntervalSince1970: 20)

        context.insert(older)
        context.insert(newer)
        try context.save()

        let all = coordinator.loadAllItems()
        XCTAssertEqual(all.map(\.cleanText), ["new", "old"])

        let limited = coordinator.loadAllItems(limit: 1)
        XCTAssertEqual(limited.map(\.cleanText), ["new"])
    }

    func testQueuedJobEventuallyCreatesItemWhenRetryWorkerRuns() async throws {
        api.results = [
            .failure(MemoryProcessingAPIError.serverError(503, "Unavailable")),
            .success(
                ProcessMemoryResponseDTO(
                    cleanText: "Efter retry",
                    suggestedType: "Insight",
                    tags: ["retry", "memory"],
                    embedding: [0.3, 0.4]
                )
            )
        ]

        let firstOutcome = await coordinator.save(text: "Retry flow", language: "sv")
        XCTAssertEqual(firstOutcome, .queued)

        clock.now = clock.now.addingTimeInterval(31)
        await coordinator.processPendingJobs()

        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<LongTermMemoryItem>())
        let jobs = try context.fetch(FetchDescriptor<LongTermMemoryPendingJob>())

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].cleanText, "Efter retry")
        XCTAssertTrue(jobs.isEmpty)
    }

    func testValueCopiedCoordinatorCanProcessExistingQueue() async throws {
        api.results = [
            .failure(MemoryProcessingAPIError.serverError(503, "Unavailable")),
            .success(
                ProcessMemoryResponseDTO(
                    cleanText: "Saved from copied coordinator",
                    suggestedType: "Insight",
                    tags: ["copy"],
                    embedding: [0.8]
                )
            )
        ]

        let firstOutcome = await coordinator.save(text: "Copy me", language: "sv")
        XCTAssertEqual(firstOutcome, .queued)

        let copiedCoordinator = coordinator!
        clock.now = clock.now.addingTimeInterval(31)
        await copiedCoordinator.processPendingJobs()

        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<LongTermMemoryItem>())
        let jobs = try context.fetch(FetchDescriptor<LongTermMemoryPendingJob>())

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].cleanText, "Saved from copied coordinator")
        XCTAssertTrue(jobs.isEmpty)
    }

    func testRepeated503EventuallyMarksJobFailedAfterMaxRetries() async throws {
        api.results = Array(
            repeating: .failure(MemoryProcessingAPIError.serverError(503, "Unavailable")),
            count: 8
        )

        let firstOutcome = await coordinator.save(text: "Always down", language: "sv")
        XCTAssertEqual(firstOutcome, .queued)

        // Initial save() consumes attempt #1. Advance time and process six more attempts.
        // On attempt #7 the job should transition to failed.
        for _ in 0..<6 {
            clock.now = clock.now.addingTimeInterval(60_000)
            await coordinator.processPendingJobs()
        }

        let context = ModelContext(container)
        let jobs = try context.fetch(FetchDescriptor<LongTermMemoryPendingJob>())
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs[0].status, .failed)
        XCTAssertEqual(jobs[0].attemptCount, 7)
        XCTAssertEqual(jobs[0].lastError, "Tjänsten för minnessparning är tillfälligt otillgänglig (503).")
    }

    func testProcessMemoryResponseDTODecodesLegacySuggestedTypePayload() throws {
        let json = """
        {
          "cleanText": "legacy",
          "suggestedType": "Insight",
          "tags": ["legacy"],
          "embedding": [0.1]
        }
        """

        let decoded = try JSONDecoder().decode(
            ProcessMemoryResponseDTO.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.cleanText, "legacy")
        XCTAssertEqual(decoded.cognitiveType, "Insight")
        XCTAssertEqual(decoded.domain, "other")
        XCTAssertEqual(decoded.actionState, "info")
        XCTAssertEqual(decoded.timeRelation, "none")
    }

    func testLongTermMemorySyncRecordDecodesLegacySuggestedTypePayload() throws {
        let json = """
        {
          "id": "2D2D4A3B-8A1F-4A1D-BF6A-C5D391E6EAA8",
          "originalText": "raw",
          "cleanText": "clean",
          "suggestedType": "Idea",
          "tags": ["legacy"],
          "embedding": [0.2],
          "createdAt": "2026-02-28T12:00:00Z",
          "isUserEdited": false
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LongTermMemorySyncRecord.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.cognitiveType, "Idea")
        XCTAssertEqual(decoded.domain, "other")
        XCTAssertEqual(decoded.actionState, "info")
        XCTAssertEqual(decoded.timeRelation, "none")
        XCTAssertNil(decoded.updatedAt)
    }
}

private final class MockMemoryProcessingAPI: MemoryProcessingAPI {
    var results: [Result<ProcessMemoryResponseDTO, Error>] = []

    func processMemory(text: String, language: String) async throws -> ProcessMemoryResponseDTO {
        if results.isEmpty {
            return ProcessMemoryResponseDTO(
                cleanText: text,
                suggestedType: "Insight",
                tags: ["memory"],
                embedding: [0.0]
            )
        }

        let next = results.removeFirst()
        return try next.get()
    }
}
