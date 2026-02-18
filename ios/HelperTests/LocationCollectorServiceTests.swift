import XCTest
import SwiftData
@testable import Helper

@MainActor
final class LocationCollectorServiceTests: XCTestCase {

    private var modelContainer: ModelContainer!
    private var mockSnapshotService: MockLocationSnapshotService!
    private var service: LocationCollectorService!

    override func setUpWithError() throws {
        let schema = Schema([IndexedLocationSnapshot.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])

        mockSnapshotService = MockLocationSnapshotService()
        service = LocationCollectorService(
            snapshotService: mockSnapshotService,
            nowProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        mockSnapshotService = nil
        service = nil
    }

    func testRetentionPeriodIs7Days() {
        XCTAssertEqual(LocationCollectorService.retentionDays, 7)
    }

    func testPruneExpiredRemovesOldSnapshots() throws {
        let context = modelContainer.mainContext
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        context.insert(makeSnapshot(id: "location:old", observedAt: now.addingTimeInterval(-8 * 24 * 60 * 60)))
        context.insert(makeSnapshot(id: "location:recent", observedAt: now.addingTimeInterval(-1 * 24 * 60 * 60)))
        try context.save()

        let pruned = try service.pruneExpired(in: context)
        XCTAssertEqual(pruned, 1)

        let remaining = try context.fetch(FetchDescriptor<IndexedLocationSnapshot>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, "location:recent")
    }

    func testCollectDeltaFiltersByRetentionAndCheckpoint() throws {
        let context = modelContainer.mainContext
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let old = makeSnapshot(
            id: "location:old",
            observedAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-8 * 24 * 60 * 60)
        )
        let beforeCheckpoint = makeSnapshot(
            id: "location:before",
            observedAt: now.addingTimeInterval(-2 * 60 * 60),
            updatedAt: now.addingTimeInterval(-2 * 60 * 60)
        )
        let afterCheckpoint = makeSnapshot(
            id: "location:after",
            observedAt: now.addingTimeInterval(-30 * 60),
            updatedAt: now.addingTimeInterval(-30 * 60)
        )

        context.insert(old)
        context.insert(beforeCheckpoint)
        context.insert(afterCheckpoint)
        try context.save()

        let checkpoint = now.addingTimeInterval(-60 * 60)
        let delta = try service.collectDelta(since: checkpoint, in: context)

        XCTAssertEqual(delta.items.count, 1)
        XCTAssertEqual(delta.items.first?.id, "location:after")
        XCTAssertEqual(delta.items.first?.source, "location")
        XCTAssertEqual(delta.entries.first?.source, .location)
    }

    func testCaptureAndIndexUsesSnapshotService() async throws {
        let context = modelContainer.mainContext
        mockSnapshotService.nextSnapshot = makeSnapshot(
            id: "location:captured",
            observedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let count = try await service.captureAndIndex(in: context)

        XCTAssertEqual(count, 1)
        XCTAssertEqual(mockSnapshotService.captureCallCount, 1)

        let rows = try context.fetch(FetchDescriptor<IndexedLocationSnapshot>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, "location:captured")
    }

    func testLastSnapshotDateReturnsMostRecentObservedAt() throws {
        let context = modelContainer.mainContext
        let older = makeSnapshot(id: "location:1", observedAt: Date(timeIntervalSince1970: 100))
        let newer = makeSnapshot(id: "location:2", observedAt: Date(timeIntervalSince1970: 200))
        context.insert(older)
        context.insert(newer)
        try context.save()

        let last = try service.lastSnapshotDate(in: context)
        XCTAssertEqual(last, Date(timeIntervalSince1970: 200))
    }

    private func makeSnapshot(
        id: String,
        observedAt: Date,
        updatedAt: Date? = nil
    ) -> IndexedLocationSnapshot {
        IndexedLocationSnapshot(
            id: id,
            title: "Nära Test",
            bodySnippet: "Test body",
            roundedLat: 59.33,
            roundedLon: 18.07,
            accuracyMeters: 100,
            placeLabel: "Testplats",
            observedAt: observedAt,
            createdAt: observedAt,
            updatedAt: updatedAt ?? observedAt
        )
    }
}

private final class MockLocationSnapshotService: LocationSnapshoting, @unchecked Sendable {
    var shouldThrow: Error?
    var nextSnapshot: IndexedLocationSnapshot?
    private(set) var captureCallCount = 0

    @MainActor
    func captureSnapshot(in context: ModelContext) async throws -> LocationSnapshotResult {
        captureCallCount += 1

        if let shouldThrow {
            throw shouldThrow
        }

        let snapshot = nextSnapshot ?? IndexedLocationSnapshot(
            id: "location:mock:\(UUID().uuidString)",
            title: "Nära Mock",
            bodySnippet: "Mock body",
            roundedLat: 59.33,
            roundedLon: 18.07,
            accuracyMeters: 100,
            placeLabel: "Mockplats",
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        context.insert(snapshot)
        try context.save()

        return LocationSnapshotResult(snapshot: snapshot, fallbackUsed: false)
    }

    func lastSnapshot(maxAge: TimeInterval, in context: ModelContext) throws -> IndexedLocationSnapshot? {
        var descriptor = FetchDescriptor<IndexedLocationSnapshot>(
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
