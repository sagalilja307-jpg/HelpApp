import Foundation
import SwiftData

extension ContactsCollectorService {

    // MARK: - Collect

    func collectDelta(
        since: Date?,
        in context: ModelContext
    ) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        let op = "ContactsCollect"
        DataSourceDebug.start(op)
        do {
            let filtered: [IndexedContact]
            if let since {
                let descriptor = FetchDescriptor<IndexedContact>(
                    predicate: #Predicate { $0.updatedAt > since },
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
                filtered = try context.fetch(descriptor)
            } else {
                let descriptor = FetchDescriptor<IndexedContact>(
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
                filtered = try context.fetch(descriptor)
            }

            DataSourceDebug.success(op, count: filtered.count)
            return (
                filtered.map(Self.mapIndexedContact),
                filtered.map(Self.makeEntry)
            )
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }
}
