import Foundation
import SwiftData

extension FilesImportService {

    // MARK: - Collect

    func collectDelta(
        since: Date?,
        in context: ModelContext
    ) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        let op = "FilesCollect"
        DataSourceDebug.start(op)
        do {
            let descriptor = FetchDescriptor<IndexedFileDocument>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )

            let rows = try context.fetch(descriptor)
            let filtered = rows.filter { row in
                guard let since else { return true }
                return row.updatedAt > since
            }

            DataSourceDebug.success(op, count: filtered.count)
            return (
                filtered.map(Self.mapIndexedFile),
                filtered.map(Self.makeEntry)
            )
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }

    func hasImportedDocuments(
        in context: ModelContext
    ) throws -> Bool {
        if sourceConnectionStore.hasImportedFiles() {
            return true
        }

        var descriptor = FetchDescriptor<IndexedFileDocument>()
        descriptor.fetchLimit = 1
        let hasImported = try !context.fetch(descriptor).isEmpty

        if hasImported {
            sourceConnectionStore.setHasImportedFiles(true)
        }

        return hasImported
    }
}
