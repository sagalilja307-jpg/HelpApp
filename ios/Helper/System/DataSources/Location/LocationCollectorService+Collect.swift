import Foundation
import SwiftData

extension LocationCollectorService {

    // MARK: - Collect

    func collectDelta(
        since: Date?,
        in context: ModelContext
    ) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        let op = "LocationCollect"
        DataSourceDebug.start(op)
        do {
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

            DataSourceDebug.success(op, count: filtered.count)
            return (items, entries)
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }

    // MARK: - Prune

    func pruneExpired(
        in context: ModelContext
    ) throws -> Int {
        let op = "LocationPruneExpired"
        DataSourceDebug.start(op)
        do {
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

            DataSourceDebug.success(op, count: expired.count)
            return expired.count
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
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
