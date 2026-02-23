// PhotoOCR.swift
// Utility for recognizing text from images using Vision

import UIKit
import Vision

/// Performs OCR (Optical Character Recognition) on a given UIImage.
enum PhotoOCR {

    /// Recognizes text from an image asynchronously using Vision.
    /// - Parameter image: The UIImage to process.
    /// - Returns: A string containing all recognized text, separated by line breaks.
    static func recognize(from image: UIImage) async -> String {
        guard let cg = image.cgImage else {
            print("PhotoOCR: Unable to get CGImage from UIImage.")
            return ""
        }

        // Run Vision in a detached background task to avoid Sendable issues
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLanguages = ["sv-SE", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            let handler = VNImageRequestHandler(cgImage: cg, options: [:])

            do {
                try handler.perform([request])

                let lines = request.results?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []

                return lines.joined(separator: "\n")
            } catch {
                print("PhotoOCR: OCR failed with error: \(error.localizedDescription)")
                return ""
            }

        }.value
    }
}
