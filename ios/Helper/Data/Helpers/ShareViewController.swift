import UIKit
import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        handleSharedContent()
    }

    private func handleSharedContent() {
        guard
            let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
            let attachments = extensionItem.attachments
        else {
            close()
            return
        }

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                loadText(from: provider)
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                loadURL(from: provider)
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                loadImage(from: provider)
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                loadPDF(from: provider)
                return
            }
        }

        close()
    }
}

private extension ShareViewController {

    func loadText(from provider: NSItemProvider) {
        provider.loadItem(
            forTypeIdentifier: UTType.plainText.identifier,
            options: nil
        ) { item, _ in
            guard let text = item as? String else {
                self.close()
                return
            }

            self.appendSharedItem(
                kind: .text,
                value: text,
                source: "share_text"
            )
            self.close()
        }
    }

    func loadURL(from provider: NSItemProvider) {
        provider.loadItem(
            forTypeIdentifier: UTType.url.identifier,
            options: nil
        ) { item, _ in
            guard let url = item as? URL else {
                self.close()
                return
            }

            self.appendSharedItem(
                kind: .url,
                value: url.absoluteString,
                source: "share_url"
            )
            self.close()
        }
    }

    func loadImage(from provider: NSItemProvider) {
        provider.loadItem(
            forTypeIdentifier: UTType.image.identifier,
            options: nil
        ) { item, _ in
            guard let imageURL = item as? URL else {
                self.close()
                return
            }

            self.appendSharedItem(
                kind: .imageFile,
                value: imageURL.absoluteString,
                source: "share_image"
            )
            self.close()
        }
    }

    func loadPDF(from provider: NSItemProvider) {
        provider.loadItem(
            forTypeIdentifier: UTType.pdf.identifier,
            options: nil
        ) { item, _ in
            guard let pdfURL = item as? URL else {
                self.close()
                return
            }

            self.appendSharedItem(
                kind: .pdfFile,
                value: pdfURL.absoluteString,
                source: "share_pdf"
            )
            self.close()
        }
    }

    func appendSharedItem(kind: SharedItemKind, value: String, source: String) {
        guard let defaults = UserDefaults(suiteName: AppIntegrationConfig.appGroupIdentifier) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let existing: SharedItemsEnvelope
        if let data = defaults.data(forKey: AppIntegrationConfig.sharedItemsKey),
           let decoded = try? decoder.decode(SharedItemsEnvelope.self, from: data) {
            existing = decoded
        } else {
            existing = SharedItemsEnvelope(version: .v1, items: [], createdAt: Date())
        }

        var items = existing.items
        items.append(
            SharedItemPayload(
                id: UUID().uuidString,
                kind: kind,
                value: value,
                source: source,
                createdAt: Date()
            )
        )

        let envelope = SharedItemsEnvelope(version: .v1, items: items, createdAt: existing.createdAt)
        if let encoded = try? encoder.encode(envelope) {
            defaults.set(encoded, forKey: AppIntegrationConfig.sharedItemsKey)
        }
    }

    func close() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
