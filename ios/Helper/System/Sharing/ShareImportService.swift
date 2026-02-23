import Foundation
import SwiftData

struct ShareImportService {

    private let memoryService: MemoryService
    private let notesStore: NotesStoreService
    private let defaults: UserDefaults

    init(
        memoryService: MemoryService,
        notesStore: NotesStoreService = NotesStoreService(),
        defaults: UserDefaults? = UserDefaults(
            suiteName: AppIntegrationConfig.appGroupIdentifier
        )
    ) {
        self.memoryService = memoryService
        self.notesStore = notesStore
        self.defaults = defaults ?? .standard
    }

    @discardableResult
    func importPendingSharedItems() throws -> Int {

        guard let data = defaults.data(
            forKey: AppIntegrationConfig.sharedItemsKey
        ) else {
            return 0
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let envelope = try? decoder.decode(
            SharedItemsEnvelope.self,
            from: data
        ) else {
            defaults.removeObject(
                forKey: AppIntegrationConfig.sharedItemsKey
            )
            return 0
        }

        let context = memoryService.context()

        var imported = 0

        for item in envelope.items {

            let note = buildImportedNote(from: item)

            _ = try notesStore.upsertImportedNote(
                title: note.title,
                body: note.body,
                source: note.source,
                externalRef: item.id,
                in: context
            )

            imported += 1
        }

        defaults.removeObject(
            forKey: AppIntegrationConfig.sharedItemsKey
        )

        return imported
    }

    // MARK: - Helpers

    private func buildImportedNote(
        from item: SharedItemPayload
    ) -> (title: String, body: String, source: String) {

        switch item.kind {

        case .text:
            let trimmed = item.value
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let firstLine = trimmed
                .split(separator: "\n")
                .first
                .map(String.init)

            let title = firstLine?.isEmpty == false
                ? firstLine!
                : "Delad text"

            return (
                title: title,
                body: trimmed,
                source: item.source
            )

        case .url:
            return (
                title: "Delad länk",
                body: item.value,
                source: item.source
            )

        case .imageFile:
            return (
                title: "Delad bild",
                body: "Filreferens: \(item.value)",
                source: item.source
            )

        case .pdfFile:
            return (
                title: "Delad PDF",
                body: "Filreferens: \(item.value)",
                source: item.source
            )
        }
    }
}
// MOVE FILE TO: /Users/sagalilja/Library/Mobile Documents/com~apple~CloudDocs/Helper/ios/Helper/Data/Services/Sharing/ShareImportService.swift
