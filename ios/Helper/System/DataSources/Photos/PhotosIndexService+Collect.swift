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
            let filtered: [IndexedPhotoAsset]
            if let since {
                let descriptor = FetchDescriptor<IndexedPhotoAsset>(
                    predicate: #Predicate { $0.updatedAt > since },
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
                filtered = try context.fetch(descriptor)
            } else {
                let descriptor = FetchDescriptor<IndexedPhotoAsset>(
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
                filtered = try context.fetch(descriptor)
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
