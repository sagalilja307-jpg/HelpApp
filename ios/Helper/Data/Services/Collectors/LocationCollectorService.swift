import Foundation
import SwiftData

protocol LocationCollecting: Sendable {

    func captureAndIndex(
        in context: ModelContext
    ) async throws -> Int

    func collectDelta(
        since: Date?,
        in context: ModelContext
    ) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry])

    func pruneExpired(
        in context: ModelContext
    ) throws -> Int

    func lastSnapshotDate(
        in context: ModelContext
    ) throws -> Date?
}

struct LocationCollectorService: LocationCollecting {

    private let snapshotService: LocationSnapshoting
    private let nowProvider: () -> Date

    static let retentionDays: Int = 7

    init(
        snapshotService: LocationSnapshoting,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.snapshotService = snapshotService
        self.nowProvider = nowProvider
    }

    // MARK: - Capture

    func captureAndIndex(
        in context: ModelContext
    ) async throws -> Int {

        _ = try pruneExpired(in: context)

        _ = try await snapshotService.captureSnapshot(
            in: context
        )

        return 1
    }

    // MARK: - Collect

    func collectDelta(
        since: Date?,
        in context: ModelContext
    ) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {

        let retentionCutoff = nowProvider()
            .addingTimeInterval(-Double(Self.retentionDays * 24 * 60 * 60))

        let descriptor = FetchDescriptor<IndexedLocationSnapshot>(
            predicate: #Predicate { $0.observedAt >= retentionCutoff },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let rows = try context.fetch(descriptor)

        let filtered = rows.filter { row in
            guard let since else { return true }
            return row.updatedAt > since
        }

        let items = filtered.map(Self.mapToUnifiedItem)
        let entries = filtered.map(Self.makeEntry)

        return (items, entries)
    }

    // MARK: - Prune

    func pruneExpired(
        in context: ModelContext
    ) throws -> Int {

        let cutoff = nowProvider()
            .addingTimeInterval(-Double(Self.retentionDays * 24 * 60 * 60))

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

    func lastSnapshotDate(
        in context: ModelContext
    ) throws -> Date? {

        var descriptor = FetchDescriptor<IndexedLocationSnapshot>(
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        return try context.fetch(descriptor).first?.observedAt
    }
}
