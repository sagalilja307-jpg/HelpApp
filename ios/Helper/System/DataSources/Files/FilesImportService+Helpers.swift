import CryptoKit
import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
@preconcurrency import UIKit
#endif

// MARK: - Helpers

extension FilesImportService {

    func extractBody(
        from url: URL,
        uti: String,
        fileName: String,
        sizeBytes: Int
    ) async -> String {

        if let text = textExtractionService.extractText(from: url),
           !text.isEmpty {
            return text
        }

        if sourceConnectionStore.isOCREnabled(for: .files),
           let ocrText = await performImageOCRIfPossible(url: url, uti: uti),
           !ocrText.isEmpty {
            return ocrText
        }

        return "Fil: \(fileName)\nTyp: \(uti)\nStorlek: \(sizeBytes) bytes"
    }

    func performImageOCRIfPossible(
        url: URL,
        uti: String
    ) async -> String? {

        #if canImport(UIKit)
        guard let type = UTType(uti),
              type.conforms(to: .image) else { return nil }

        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }

        let text = await PhotoOCR.recognize(from: image)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? nil : text
        #else
        return nil
        #endif
    }

    static func stableHash(
        url: URL,
        fileName: String,
        size: Int,
        modifiedAt: Date
    ) -> String {

        let signature = "\(url.path)|\(fileName)|\(size)|\(modifiedAt.timeIntervalSince1970)"
        let digest = SHA256.hash(data: Data(signature.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
