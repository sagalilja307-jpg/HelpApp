import Foundation
import SwiftData

// MARK: - Protocol

protocol LocationCollecting: Sendable {
    func captureAndIndex() async throws -> Int
    func collectDelta(since: Date?) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry])
    func pruneExpired() throws -> Int
    func lastSnapshotDate() throws -> Date?
}

// MARK: - Service

struct LocationCollectorService: LocationCollecting {
    
    private let memoryService: MemoryService?
    private let modelContext: ModelContext?
    private let snapshotService: LocationSnapshoting
    private let nowProvider: () -> Date
    
    /// Retention period for location snapshots: 7 days
    static let retentionDays: Int = 7
    
    init(
        memoryService: MemoryService,
        snapshotService: LocationSnapshoting,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.memoryService = memoryService
        self.modelContext = nil
        self.snapshotService = snapshotService
        self.nowProvider = nowProvider
    }
    
    init(
        context: ModelContext,
        snapshotService: LocationSnapshoting,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.memoryService = nil
        self.modelContext = context
        self.snapshotService = snapshotService
        self.nowProvider = nowProvider
    }
    
    private func context() -> ModelContext {
        if let modelContext { return modelContext }
        return memoryService!.context()
    }
    
    // MARK: - Public API
    
    /// Capture current location and index it, then prune old data
    func captureAndIndex() async throws -> Int {
        // First prune expired snapshots
        _ = try pruneExpired()
        
        // Capture new snapshot
        _ = try await snapshotService.captureSnapshot()
        
        return 1
    }
    
    /// Collect location snapshots modified since checkpoint as DTOs
    func collectDelta(since: Date?) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        let context = context()
        
        // Apply retention filter
        let retentionCutoff = nowProvider().addingTimeInterval(-Double(Self.retentionDays * 24 * 60 * 60))
        
        let descriptor = FetchDescriptor<IndexedLocationSnapshot>(
            predicate: #Predicate { $0.observedAt >= retentionCutoff },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        let rows = try context.fetch(descriptor)
        
        // Filter by checkpoint if provided
        let filtered: [IndexedLocationSnapshot]
        if let since {
            filtered = rows.filter { $0.updatedAt > since }
        } else {
            filtered = rows
        }
        
        let items = filtered.map(Self.mapToUnifiedItem)
        let entries = filtered.map(Self.makeEntry)
        
        return (items, entries)
    }
    
    /// Remove snapshots older than retention period
    func pruneExpired() throws -> Int {
        let context = context()
        let cutoff = nowProvider().addingTimeInterval(-Double(Self.retentionDays * 24 * 60 * 60))
        
        let descriptor = FetchDescriptor<IndexedLocationSnapshot>(
            predicate: #Predicate { $0.observedAt < cutoff }
        )
        
        let expired = try context.fetch(descriptor)
        
        for snapshot in expired {
            context.delete(snapshot)
        }
        
        if !expired.isEmpty {
            try context.save()
        }
        
        return expired.count
    }
    
    /// Get the date of the most recent snapshot
    func lastSnapshotDate() throws -> Date? {
        let context = context()
        
        var descriptor = FetchDescriptor<IndexedLocationSnapshot>(
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        
        let results = try context.fetch(descriptor)
        return results.first?.observedAt
    }
}

// MARK: - Mapping Helpers

extension LocationCollectorService {
    
    static func mapToUnifiedItem(_ snapshot: IndexedLocationSnapshot) -> UnifiedItemDTO {
        UnifiedItemDTO(
            id: snapshot.id,
            source: "locations",
            type: .location,
            title: snapshot.title,
            body: snapshot.bodySnippet,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt,
            startAt: snapshot.observedAt,
            endAt: nil,
            dueAt: nil,
            status: [
                "accuracy_m": AnyCodable(snapshot.accuracyMeters),
                "lat_bucket": AnyCodable(snapshot.roundedLat),
                "lon_bucket": AnyCodable(snapshot.roundedLon),
                "place_label": AnyCodable(snapshot.placeLabel),
                "is_approximate": AnyCodable(true)
            ]
        )
    }
    
    static func makeEntry(_ snapshot: IndexedLocationSnapshot) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(),
            source: .location,
            title: snapshot.title,
            body: snapshot.bodySnippet.isEmpty ? nil : snapshot.bodySnippet,
            date: snapshot.observedAt
        )
    }
}
