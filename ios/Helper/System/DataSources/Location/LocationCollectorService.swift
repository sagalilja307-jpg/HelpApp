import Foundation
import SwiftData

protocol LocationCollecting: Sendable {

    @MainActor
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

    let snapshotService: LocationSnapshoting
    let nowProvider: () -> Date

    static let retentionDays: Int = 7

    init(
        snapshotService: LocationSnapshoting,
        nowProvider: @escaping () -> Date = DateService.shared.now
    ) {
        self.snapshotService = snapshotService
        self.nowProvider = nowProvider
    }

    // MARK: - Capture

    @MainActor
    func captureCurrentLocation(in context: ModelContext) async throws -> IndexedLocationSnapshot {
        let result = try await snapshotService.captureSnapshot(in: context)
        return result.snapshot
    }

    func fetchRecentLocations(limit: Int = 50, in context: ModelContext) throws -> [IndexedLocationSnapshot] {
        var descriptor = FetchDescriptor<IndexedLocationSnapshot>(
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func searchLocationsByName(_ searchText: String, in context: ModelContext) throws -> [IndexedLocationSnapshot] {
        let lowercased = searchText.lowercased()
        let descriptor = FetchDescriptor<IndexedLocationSnapshot>(
            predicate: #Predicate { location in
                location.placeLabel.localizedStandardContains(lowercased) ||
                location.title.localizedStandardContains(lowercased) ||
                location.bodySnippet.localizedStandardContains(lowercased)
            },
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    @MainActor
    func captureAndIndex(
        in context: ModelContext
    ) async throws -> Int {
        let op = "LocationCaptureAndIndex"
        DataSourceDebug.start(op)
        do {
            _ = try pruneExpired(in: context)

            _ = try await snapshotService.captureSnapshot(
                in: context
            )
            DataSourceDebug.success(op, count: 1)
            return 1
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }
}
