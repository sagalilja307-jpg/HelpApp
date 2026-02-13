import XCTest
import SwiftData
@testable import Helper

@MainActor
final class LocationCollectorServiceTests: XCTestCase {
    
    private var modelContainer: ModelContainer!
    private var mockSnapshotService: MockLocationSnapshotService!
    private var service: LocationCollectorService!
    
    override func setUpWithError() throws {
        let schema = Schema([
            IndexedLocationSnapshot.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        
        mockSnapshotService = MockLocationSnapshotService()
        let context = modelContainer.mainContext
        
        service = LocationCollectorService(
            context: context,
            snapshotService: mockSnapshotService,
            nowProvider: { Date() }
        )
    }
    
    override func tearDownWithError() throws {
        modelContainer = nil
        mockSnapshotService = nil
        service = nil
    }
    
    // MARK: - Retention Tests
    
    func testRetentionPeriodIs7Days() {
        XCTAssertEqual(LocationCollectorService.retentionDays, 7)
    }
    
    func testPruneExpiredRemovesOldSnapshots() throws {
        let context = modelContainer.mainContext
        let now = Date()
        
        // Insert old snapshot (8 days old)
        let oldSnapshot = IndexedLocationSnapshot(
            id: "location:old",
            title: "Old",
            bodySnippet: "Old snapshot",
            roundedLat: 59.33,
            roundedLon: 18.07,
            accuracyMeters: 100,
            placeLabel: "Old Place",
            observedAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
            createdAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-8 * 24 * 60 * 60)
        )
        context.insert(oldSnapshot)
        
        // Insert recent snapshot (1 day old)
        let recentSnapshot = IndexedLocationSnapshot(
            id: "location:recent",
            title: "Recent",
            bodySnippet: "Recent snapshot",
            roundedLat: 59.34,
            roundedLon: 18.08,
            accuracyMeters: 50,
            placeLabel: "Recent Place",
            observedAt: now.addingTimeInterval(-1 * 24 * 60 * 60),
            createdAt: now.addingTimeInterval(-1 * 24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-1 * 24 * 60 * 60)
        )
        context.insert(recentSnapshot)
        
        try context.save()
        
        // Prune expired
        let pruned = try service.pruneExpired()
        
        XCTAssertEqual(pruned, 1, "Should prune 1 old snapshot")
        
        // Verify only recent snapshot remains
        let remaining = try context.fetch(FetchDescriptor<IndexedLocationSnapshot>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, "location:recent")
    }
    
    // MARK: - DTO Mapping Tests
    
    func testMapToUnifiedItemCreatesCorrectDTO() {
        let now = Date()
        let snapshot = IndexedLocationSnapshot(
            id: "location:59.33:18.07:12345",
            title: "Nära Stockholm",
            bodySnippet: "Test body",
            roundedLat: 59.33,
            roundedLon: 18.07,
            accuracyMeters: 100,
            placeLabel: "Stockholm",
            observedAt: now,
            createdAt: now,
            updatedAt: now
        )
        
        let dto = LocationCollectorService.mapToUnifiedItem(snapshot)
        
        XCTAssertEqual(dto.id, "location:59.33:18.07:12345")
        XCTAssertEqual(dto.source, "locations")
        XCTAssertEqual(dto.type, .location)
        XCTAssertEqual(dto.title, "Nära Stockholm")
        XCTAssertEqual(dto.body, "Test body")
        
        // Verify status fields
        let status = dto.status
        XCTAssertEqual(status["accuracy_m"]?.value as? Double, 100)
        XCTAssertEqual(status["lat_bucket"]?.value as? Double, 59.33)
        XCTAssertEqual(status["lon_bucket"]?.value as? Double, 18.07)
        XCTAssertEqual(status["place_label"]?.value as? String, "Stockholm")
        XCTAssertEqual(status["is_approximate"]?.value as? Bool, true)
    }
    
    func testMakeEntryCreatesCorrectEntry() {
        let now = Date()
        let snapshot = IndexedLocationSnapshot(
            id: "location:test",
            title: "Nära Göteborg",
            bodySnippet: "Body snippet",
            roundedLat: 57.71,
            roundedLon: 11.97,
            accuracyMeters: 200,
            placeLabel: "Göteborg",
            observedAt: now,
            createdAt: now,
            updatedAt: now
        )
        
        let entry = LocationCollectorService.makeEntry(snapshot)
        
        XCTAssertEqual(entry.source, .location)
        XCTAssertEqual(entry.title, "Nära Göteborg")
        XCTAssertEqual(entry.body, "Body snippet")
        XCTAssertEqual(entry.date, now)
    }
    
    // MARK: - Delta Collection Tests
    
    func testCollectDeltaFiltersOldSnapshots() throws {
        let context = modelContainer.mainContext
        let now = Date()
        
        // Insert snapshot older than 7 days
        let oldSnapshot = IndexedLocationSnapshot(
            id: "location:old",
            title: "Old",
            bodySnippet: "Old",
            roundedLat: 59.33,
            roundedLon: 18.07,
            accuracyMeters: 100,
            placeLabel: "Old",
            observedAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
            createdAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-8 * 24 * 60 * 60)
        )
        context.insert(oldSnapshot)
        
        // Insert recent snapshot
        let recentSnapshot = IndexedLocationSnapshot(
            id: "location:recent",
            title: "Recent",
            bodySnippet: "Recent",
            roundedLat: 59.34,
            roundedLon: 18.08,
            accuracyMeters: 50,
            placeLabel: "Recent",
            observedAt: now.addingTimeInterval(-1 * 24 * 60 * 60),
            createdAt: now.addingTimeInterval(-1 * 24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-1 * 24 * 60 * 60)
        )
        context.insert(recentSnapshot)
        
        try context.save()
        
        let (items, entries) = try service.collectDelta(since: nil)
        
        // Only the recent snapshot should be included
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(items.first?.id, "location:recent")
    }
    
    func testCollectDeltaRespectsCheckpoint() throws {
        let context = modelContainer.mainContext
        let now = Date()
        
        // Insert snapshot before checkpoint
        let beforeCheckpoint = IndexedLocationSnapshot(
            id: "location:before",
            title: "Before",
            bodySnippet: "Before",
            roundedLat: 59.33,
            roundedLon: 18.07,
            accuracyMeters: 100,
            placeLabel: "Before",
            observedAt: now.addingTimeInterval(-2 * 60 * 60),
            createdAt: now.addingTimeInterval(-2 * 60 * 60),
            updatedAt: now.addingTimeInterval(-2 * 60 * 60)
        )
        context.insert(beforeCheckpoint)
        
        // Insert snapshot after checkpoint
        let afterCheckpoint = IndexedLocationSnapshot(
            id: "location:after",
            title: "After",
            bodySnippet: "After",
            roundedLat: 59.34,
            roundedLon: 18.08,
            accuracyMeters: 50,
            placeLabel: "After",
            observedAt: now,
            createdAt: now,
            updatedAt: now
        )
        context.insert(afterCheckpoint)
        
        try context.save()
        
        let checkpoint = now.addingTimeInterval(-1 * 60 * 60) // 1 hour ago
        let (items, _) = try service.collectDelta(since: checkpoint)
        
        // Only the after-checkpoint snapshot should be included
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, "location:after")
    }
    
    // MARK: - ID Generation Tests
    
    func testIDUsesCorrectFormat() {
        // Verify ID format matches spec: location:{lat_bucket}:{lon_bucket}:{time_bucket_15m}
        let dto = LocationCollectorService.mapToUnifiedItem(
            IndexedLocationSnapshot(
                id: "location:59.33:18.07:202602131200",
                title: "Test",
                bodySnippet: "Test",
                roundedLat: 59.33,
                roundedLon: 18.07,
                accuracyMeters: 100,
                placeLabel: "Test",
                observedAt: Date(),
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        
        XCTAssertTrue(dto.id.hasPrefix("location:"))
        XCTAssertTrue(dto.id.contains("59.33"))
        XCTAssertTrue(dto.id.contains("18.07"))
    }
}

// MARK: - Mock Services

private final class MockLocationSnapshotService: LocationSnapshoting, @unchecked Sendable {
    var captureResult: LocationSnapshotResult?
    var shouldThrow: Error?
    
    func captureSnapshot() async throws -> LocationSnapshotResult {
        if let error = shouldThrow {
            throw error
        }
        
        if let result = captureResult {
            return result
        }
        
        let snapshot = IndexedLocationSnapshot(
            id: "location:mock:test",
            title: "Mock Location",
            bodySnippet: "Mock body",
            roundedLat: 59.33,
            roundedLon: 18.07,
            accuracyMeters: 100,
            placeLabel: "Mock Place",
            observedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )
        return LocationSnapshotResult(snapshot: snapshot, fallbackUsed: false)
    }
    
    func lastSnapshot(maxAge: TimeInterval) throws -> IndexedLocationSnapshot? {
        return nil
    }
}
