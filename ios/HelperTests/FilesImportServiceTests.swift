import XCTest
import SwiftData
@testable import Helper

@MainActor
final class FilesImportServiceTests: XCTestCase {

    func testImportAndDeltaMappingFromTextFile() async throws {
        let container = try ModelContainer(
            for: IndexedFileDocument.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let sourceStore = InMemorySourceConnectionStore()
        sourceStore.setEnabled(true, for: .files)

        let service = FilesImportService(
            context: context,
            textExtractionService: FileTextExtractionService(),
            sourceConnectionStore: sourceStore,
            nowProvider: { Date(timeIntervalSince1970: 1_700_200_000) }
        )

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = tmpDir.appendingPathComponent("travel.txt")
        try "Boarding 08:00\nGate 42".write(to: fileURL, atomically: true, encoding: .utf8)

        let importedCount = try await service.importDocuments(urls: [fileURL])
        XCTAssertEqual(importedCount, 1)
        XCTAssertTrue(try service.hasImportedDocuments())
        XCTAssertTrue(sourceStore.hasImportedFiles())

        let delta = try service.collectDelta(since: nil)
        XCTAssertEqual(delta.items.count, 1)
        XCTAssertEqual(delta.items.first?.type, .file)
        XCTAssertEqual(delta.items.first?.source, "files")
        XCTAssertEqual(delta.items.first?.title, "travel.txt")
        XCTAssertTrue(delta.items.first?.body.contains("Boarding 08:00") == true)
        XCTAssertEqual(delta.entries.first?.source, .files)
    }
}

private final class InMemorySourceConnectionStore: SourceConnectionStoring, @unchecked Sendable {
    private var enabledSources: Set<QuerySource> = []
    private var ocrSources: Set<QuerySource> = []
    private var importedFiles = false

    func isEnabled(_ source: QuerySource) -> Bool {
        enabledSources.contains(source)
    }

    func setEnabled(_ enabled: Bool, for source: QuerySource) {
        if enabled {
            enabledSources.insert(source)
        } else {
            enabledSources.remove(source)
        }
    }

    func isOCREnabled(for source: QuerySource) -> Bool {
        ocrSources.contains(source)
    }

    func setOCREnabled(_ enabled: Bool, for source: QuerySource) {
        if enabled {
            ocrSources.insert(source)
        } else {
            ocrSources.remove(source)
        }
    }

    func hasImportedFiles() -> Bool {
        importedFiles
    }

    func setHasImportedFiles(_ hasImportedFiles: Bool) {
        importedFiles = hasImportedFiles
    }
}
