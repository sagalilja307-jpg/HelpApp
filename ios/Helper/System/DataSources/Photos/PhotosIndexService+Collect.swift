import Foundation
import SwiftData

extension PhotosIndexService {

    // MARK: - Collect

    func collectDelta(
        since: Date?,
        in context: ModelContext
    ) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        let op = "PhotosCollect"
        DataSourceDebug.start(op)
        do {
            let descriptor = FetchDescriptor<IndexedPhotoAsset>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )

            let rows = try context.fetch(descriptor)
            let filtered = rows.filter { row in
                guard let since else { return true }
                return row.updatedAt > since
            }

            DataSourceDebug.success(op, count: filtered.count)
            return (
                filtered.map(Self.mapIndexedAsset),
                filtered.map(Self.makeEntry)
            )
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }
}
