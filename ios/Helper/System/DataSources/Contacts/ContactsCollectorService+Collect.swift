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
            let descriptor = FetchDescriptor<IndexedContact>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )

            let rows = try context.fetch(descriptor)
            let filtered = rows.filter { row in
                guard let since else { return true }
                return row.updatedAt > since
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
