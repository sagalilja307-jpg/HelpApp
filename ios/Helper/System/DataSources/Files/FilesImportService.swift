import Foundation
import SwiftData
import UniformTypeIdentifiers

protocol FilesImporting {
    @MainActor
    func importDocuments(
        urls: [URL],
        in context: ModelContext
    ) async throws -> Int

    func collectDelta(
        since: Date?,
        in context: ModelContext
    ) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry])

    func hasImportedDocuments(
        in context: ModelContext
    ) throws -> Bool
}

struct FilesImportService: FilesImporting {

    let textExtractionService: FileTextExtractionService
    let sourceConnectionStore: SourceConnectionStoring
    let nowProvider: () -> Date

    init(
        textExtractionService: FileTextExtractionService = FileTextExtractionService(),
        sourceConnectionStore: SourceConnectionStoring = SourceConnectionStore.shared,
        nowProvider: @escaping () -> Date = DateService.shared.now
    ) {
        self.textExtractionService = textExtractionService
        self.sourceConnectionStore = sourceConnectionStore
        self.nowProvider = nowProvider
    }

    // MARK: - Import

    @MainActor
    func importFile(at url: URL, in context: ModelContext) async throws -> IndexedFileDocument {
        _ = try await importDocuments(urls: [url], in: context)
        
        let values = try url.resourceValues(forKeys: [
            .nameKey,
            .contentTypeKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        
        let fileName = values.name ?? url.lastPathComponent
        let size = max(0, values.fileSize ?? 0)
        let modifiedAt = values.contentModificationDate ?? DateService.shared.now()
        
        let stableHash = Self.stableHash(
            url: url,
            fileName: fileName,
            size: size,
            modifiedAt: modifiedAt
        )
        
        let descriptor = FetchDescriptor<IndexedFileDocument>(
            predicate: #Predicate { $0.stableHash == stableHash }
        )
        
        guard let doc = try context.fetch(descriptor).first else {
            throw NSError(domain: "FilesImportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to find imported file"])
        }
        
        return doc
    }
    
    func fetchIndexedFile(identifier: String, in context: ModelContext) throws -> IndexedFileDocument? {
        let descriptor = FetchDescriptor<IndexedFileDocument>(
            predicate: #Predicate { $0.id == identifier }
        )
        return try context.fetch(descriptor).first
    }
    
    func searchFilesByContent(_ searchText: String, in context: ModelContext) throws -> [IndexedFileDocument] {
        let lowercased = searchText.lowercased()
        let descriptor = FetchDescriptor<IndexedFileDocument>(
            predicate: #Predicate { file in
                file.fileName.localizedStandardContains(lowercased) ||
                file.bodySnippet.localizedStandardContains(lowercased)
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    @MainActor
    func importDocuments(
        urls: [URL],
        in context: ModelContext
    ) async throws -> Int {
        let op = "FilesImportDocuments"
        DataSourceDebug.start(op)

        guard !urls.isEmpty else { return 0 }

        do {
            let existing = try context.fetch(FetchDescriptor<IndexedFileDocument>())
            var existingByHash: [String: IndexedFileDocument] =
                Dictionary(uniqueKeysWithValues: existing.map { ($0.stableHash, $0) })

            var changed = 0
            let now = nowProvider()

            for url in urls {

                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }

                let values = try url.resourceValues(forKeys: [
                    .nameKey,
                    .contentTypeKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ])

                let fileName = values.name ?? url.lastPathComponent
                let uti = values.contentType?.identifier ?? "public.data"
                let size = max(0, values.fileSize ?? 0)
                let modifiedAt = values.contentModificationDate ?? now

                let stableHash = Self.stableHash(
                    url: url,
                    fileName: fileName,
                    size: size,
                    modifiedAt: modifiedAt
                )

                let rowId = "file:\(stableHash)"

                let extracted = await extractBody(
                    from: url,
                    uti: uti,
                    fileName: fileName,
                    sizeBytes: size
                )

                let bookmark = try? url.bookmarkData(
                    options: [.minimalBookmark],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )

                if let row = existingByHash[stableHash] {

                    let hasChanged =
                        row.fileName != fileName ||
                        row.bodySnippet != extracted ||
                        row.uti != uti ||
                        row.sizeBytes != size ||
                        row.bookmarkData != bookmark

                    if !hasChanged { continue }

                    row.id = rowId
                    row.fileName = fileName
                    row.bodySnippet = extracted
                    row.uti = uti
                    row.sizeBytes = size
                    row.bookmarkData = bookmark
                    row.source = "files_import"
                    row.updatedAt = now

                    changed += 1

                } else {

                    let row = IndexedFileDocument(
                        id: rowId,
                        stableHash: stableHash,
                        fileName: fileName,
                        bodySnippet: extracted,
                        uti: uti,
                        sizeBytes: size,
                        bookmarkData: bookmark,
                        source: "files_import",
                        createdAt: now,
                        updatedAt: now
                    )

                    context.insert(row)
                    existingByHash[stableHash] = row
                    changed += 1
                }
            }

            if changed > 0 {
                try context.save()
                sourceConnectionStore.setHasImportedFiles(true)
            }

            DataSourceDebug.success(op, count: changed)
            return changed
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }
}
