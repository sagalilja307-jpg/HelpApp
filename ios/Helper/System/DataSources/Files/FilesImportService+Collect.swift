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
            let filtered: [IndexedFileDocument]
            if let since {
                let descriptor = FetchDescriptor<IndexedFileDocument>(
                    predicate: #Predicate { $0.updatedAt > since },
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
                filtered = try context.fetch(descriptor)
            } else {
                let descriptor = FetchDescriptor<IndexedFileDocument>(
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
                filtered = try context.fetch(descriptor)
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
