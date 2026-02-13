import Foundation
import SwiftData
import CryptoKit
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

protocol FilesImporting {
    func importDocuments(urls: [URL]) async throws -> Int
    func collectDelta(since: Date?) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry])
    func hasImportedDocuments() throws -> Bool
}

struct FilesImportService: FilesImporting {
    private let memoryService: MemoryService?
    private let modelContext: ModelContext?
    private let textExtractionService: FileTextExtractionService
    private let sourceConnectionStore: SourceConnectionStoring
    private let nowProvider: () -> Date

    init(
        memoryService: MemoryService,
        textExtractionService: FileTextExtractionService = FileTextExtractionService(),
        sourceConnectionStore: SourceConnectionStoring = SourceConnectionStore.shared,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.memoryService = memoryService
        self.modelContext = nil
        self.textExtractionService = textExtractionService
        self.sourceConnectionStore = sourceConnectionStore
        self.nowProvider = nowProvider
    }

    init(
        context: ModelContext,
        textExtractionService: FileTextExtractionService = FileTextExtractionService(),
        sourceConnectionStore: SourceConnectionStoring = SourceConnectionStore.shared,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.memoryService = nil
        self.modelContext = context
        self.textExtractionService = textExtractionService
        self.sourceConnectionStore = sourceConnectionStore
        self.nowProvider = nowProvider
    }

    func importDocuments(urls: [URL]) async throws -> Int {
        guard !urls.isEmpty else { return 0 }

        let context = context()
        let existing = try context.fetch(FetchDescriptor<IndexedFileDocument>())
        var existingByHash: [String: IndexedFileDocument] = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.stableHash, $0) }
        )

        var changed = 0
        let now = nowProvider()

        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
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
                let hasChanged = row.fileName != fileName
                    || row.bodySnippet != extracted
                    || row.uti != uti
                    || row.sizeBytes != size
                    || row.bookmarkData != bookmark

                if !hasChanged {
                    continue
                }

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

        return changed
    }

    func collectDelta(since: Date?) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        let context = context()
        let descriptor = FetchDescriptor<IndexedFileDocument>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let rows = try context.fetch(descriptor)
        let filtered = rows.filter { row in
            guard let since else { return true }
            return row.updatedAt > since
        }
        let items = filtered.map(Self.mapIndexedFile)
        let entries = filtered.map(Self.makeEntry)
        return (items, entries)
    }

    func hasImportedDocuments() throws -> Bool {
        let context = context()
        let rows = try context.fetch(FetchDescriptor<IndexedFileDocument>())
        return !rows.isEmpty
    }
}

extension FilesImportService {
    static func mapIndexedFile(_ row: IndexedFileDocument) -> UnifiedItemDTO {
        UnifiedItemDTO(
            id: row.id,
            source: "files",
            type: .file,
            title: row.fileName,
            body: row.bodySnippet,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            startAt: nil,
            endAt: nil,
            dueAt: nil,
            status: [
                "uti": AnyCodable(row.uti),
                "size_bytes": AnyCodable(row.sizeBytes),
                "bookmark_version": AnyCodable(1)
            ]
        )
    }

    static func makeEntry(_ row: IndexedFileDocument) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(),
            source: .files,
            title: row.fileName,
            body: row.bodySnippet.isEmpty ? nil : row.bodySnippet,
            date: row.updatedAt
        )
    }

    static func stableHash(url: URL, fileName: String, size: Int, modifiedAt: Date) -> String {
        let signature = "\(url.path)|\(fileName)|\(size)|\(modifiedAt.timeIntervalSince1970)"
        let digest = SHA256.hash(data: Data(signature.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension FilesImportService {
    func context() -> ModelContext {
        if let modelContext {
            return modelContext
        }
        if let memoryService {
            return memoryService.context()
        }
        fatalError("FilesImportService saknar ModelContext och MemoryService.")
    }

    func extractBody(
        from url: URL,
        uti: String,
        fileName: String,
        sizeBytes: Int
    ) async -> String {
        if let text = textExtractionService.extractText(from: url), !text.isEmpty {
            return text
        }

        if sourceConnectionStore.isOCREnabled(for: .files),
           let ocrText = await performImageOCRIfPossible(url: url, uti: uti),
           !ocrText.isEmpty {
            return ocrText
        }

        return "Fil: \(fileName)\nTyp: \(uti)\nStorlek: \(sizeBytes) bytes"
    }

    func performImageOCRIfPossible(url: URL, uti: String) async -> String? {
        #if canImport(UIKit)
        guard let type = UTType(uti), type.conforms(to: .image) else { return nil }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        let text = await PhotoOCR.recognize(from: image).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
        #else
        return nil
        #endif
    }
}
