import Foundation

@MainActor
struct ShareImportService {
    private let notesStore: NotesStoreService
    private let defaults: UserDefaults

    nonisolated init(
        notesStore: NotesStoreService,
        defaults: UserDefaults? = UserDefaults(suiteName: AppIntegrationConfig.appGroupIdentifier)
    ) {
        self.notesStore = notesStore
        self.defaults = defaults ?? .standard
    }

    @discardableResult
    func importPendingSharedItems() throws -> Int {
        guard let data = defaults.data(forKey: AppIntegrationConfig.sharedItemsKey) else {
            return 0
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let envelope = try? decoder.decode(SharedItemsEnvelope.self, from: data) else {
            defaults.removeObject(forKey: AppIntegrationConfig.sharedItemsKey)
            return 0
        }

        var imported = 0
        for item in envelope.items {
            let note = buildImportedNote(from: item)
            _ = try notesStore.upsertImportedNote(
                title: note.title,
                body: note.body,
                source: note.source,
                externalRef: item.id
            )
            imported += 1
        }

        defaults.removeObject(forKey: AppIntegrationConfig.sharedItemsKey)
        return imported
    }

    private func buildImportedNote(from item: SharedItemPayload) -> (title: String, body: String, source: String) {
        switch item.kind {
        case .text:
            let trimmed = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmed.split(separator: "\n").first.map(String.init) ?? "Delad text"
            return (title: title.isEmpty ? "Delad text" : title, body: trimmed, source: item.source)
        case .url:
            return (title: "Delad länk", body: item.value, source: item.source)
        case .imageFile:
            return (title: "Delad bild", body: "Filreferens: \(item.value)", source: item.source)
        case .pdfFile:
            return (title: "Delad PDF", body: "Filreferens: \(item.value)", source: item.source)
        }
    }
}
