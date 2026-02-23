import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

struct FileTextExtractionService {
    func extractText(from url: URL) -> String? {
        let pathExtension = url.pathExtension.lowercased()

        if Self.plainTextExtensions.contains(pathExtension) {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return Self.trimmed(content)
            }
            if let content = try? String(contentsOf: url, encoding: .utf16) {
                return Self.trimmed(content)
            }
        }

        if pathExtension == "rtf",
           let data = try? Data(contentsOf: url),
           let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
           ) {
            return Self.trimmed(attributed.string)
        }

        if pathExtension == "pdf" {
            return extractPDFText(from: url)
        }

        return nil
    }
}

private extension FileTextExtractionService {
    static let plainTextExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "json", "xml", "yaml", "yml", "log", "rtfd"
    ]

    static func trimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func extractPDFText(from url: URL) -> String? {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else { return nil }
        var chunks: [String] = []
        for idx in 0..<document.pageCount {
            guard let page = document.page(at: idx), let text = page.string else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunks.append(trimmed)
            }
        }
        return chunks.isEmpty ? nil : chunks.joined(separator: "\n")
        #else
        return nil
        #endif
    }
}
