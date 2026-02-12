
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

            // TEXT (mejl, markerad text)
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                loadText(from: provider)
                return
            }

            // URL (t.ex. mejl-länk, webb)
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                loadURL(from: provider)
                return
            }

            // BILD (screenshot av mejl)
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                loadImage(from: provider)
                return
            }

            // PDF (biljetter, kvitton)
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
            self.saveContent(text: text, source: "mail_text")
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
            self.saveContent(text: url.absoluteString, source: "mail_url")
        }
    }

    func loadImage(from provider: NSItemProvider) {
        provider.loadItem(
            forTypeIdentifier: UTType.image.identifier,
            options: nil
        ) { item, _ in
            if let imageURL = item as? URL {
                self.saveFile(url: imageURL, source: "image")
            }
            self.close()
        }
    }

    func loadPDF(from provider: NSItemProvider) {
        provider.loadItem(
            forTypeIdentifier: UTType.pdf.identifier,
            options: nil
        ) { item, _ in
            if let pdfURL = item as? URL {
                self.saveFile(url: pdfURL, source: "pdf")
            }
            self.close()
        }
    }

    func saveContent(text: String, source: String) {
        let defaults = UserDefaults(suiteName: "group.com.dittbolag.dinapp")
        defaults?.set(text, forKey: "shared_text")
        defaults?.set(source, forKey: "shared_source")
        defaults?.set(Date(), forKey: "shared_date")
        close()
    }

    func saveFile(url: URL, source: String) {
        let defaults = UserDefaults(suiteName: "group.com.dittbolag.dinapp")
        defaults?.set(url.absoluteString, forKey: "shared_file")
        defaults?.set(source, forKey: "shared_source")
        defaults?.set(Date(), forKey: "shared_date")
    }

    func close() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
