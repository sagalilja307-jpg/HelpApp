import Foundation

extension FilesImportService {

    // MARK: - Mapping

    nonisolated static func mapIndexedFile(_ file: IndexedFileDocument) -> UnifiedItemDTO {
        UnifiedItemDTO(
            id: file.id,
            source: "files",
            type: .file,
            title: file.fileName,
            body: file.bodySnippet,
            createdAt: file.createdAt,
            updatedAt: file.updatedAt,
            startAt: nil,
            endAt: nil,
            dueAt: nil,
            status: [
                "uti": AnyCodable(file.uti),
                "size_bytes": AnyCodable(file.sizeBytes),
                "has_bookmark": AnyCodable(file.bookmarkData != nil)
            ]
        )
    }

    nonisolated static func makeEntry(_ file: IndexedFileDocument) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(),
            source: .files,
            title: file.fileName,
            body: file.bodySnippet,
            date: file.updatedAt
        )
    }
}
