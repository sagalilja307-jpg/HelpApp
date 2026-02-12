// DocumentScannerView.swift
// Cleaned and refactored version

import SwiftUI
import VisionKit
import Vision
import UIKit

struct DocumentScannerView: UIViewControllerRepresentable {
    @Binding var text: String
    var append: Bool = true
    var allowRescan: Bool = true
    var recognitionLanguages: [String] = ["sv-SE", "en-US"]
    var onTextChanged: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> ScannerHostViewController {
        let host = ScannerHostViewController()
        host.coordinator = context.coordinator
        context.coordinator.host = host
        return host
    }

    func updateUIViewController(_ uiViewController: ScannerHostViewController, context: Context) {}

    // MARK: - Host ViewController

    final class ScannerHostViewController: UIViewController {
        weak var coordinator: Coordinator?
        private var didPresentOnce = false
        
        func resetPresentation() {
            didPresentOnce = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !didPresentOnce else { return }
            didPresentOnce = true
            presentScanner()
        }

        private func presentScanner() {
            guard VNDocumentCameraViewController.isSupported else {
                print("Document scanning is not supported on this device.")
                return
            }
            let scannerVC = VNDocumentCameraViewController()
            scannerVC.delegate = coordinator
            present(scannerVC, animated: true)
        }
    }

    // MARK: - OCR Text Recognizer

    private func recognizeText(from image: CGImage, languages: [String], completion: @escaping (String?) -> Void) {
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil else {
                print("OCR error: \(error!.localizedDescription)")
                completion(nil)
                return
            }

            let recognizedText = request.results?
                .compactMap { $0 as? VNRecognizedTextObservation }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")

            completion(recognizedText)
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true

        do {
            try requestHandler.perform([request])
        } catch {
            print("Failed to perform OCR request: \(error.localizedDescription)")
            completion(nil)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject,
                             VNDocumentCameraViewControllerDelegate,
                             UINavigationControllerDelegate,
                             UIImagePickerControllerDelegate {

        let parent: DocumentScannerView
        weak var host: ScannerHostViewController?

        init(parent: DocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
            print("Scanner failed: \(error.localizedDescription)")
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            controller.dismiss(animated: true)

            guard scan.pageCount > 0 else { return }

            for i in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: i)
                guard let cgImage = image.cgImage else {
                    print("Failed to get CGImage from scanned page.")
                    continue
                }

                parent.recognizeText(from: cgImage, languages: parent.recognitionLanguages) { [weak self] recognizedText in
                    DispatchQueue.main.async {
                        guard let self = self, let recognizedText = recognizedText else { return }
                        if self.parent.append {
                            self.parent.text += (self.parent.text.isEmpty ? "" : "\n") + recognizedText
                        } else {
                            self.parent.text = recognizedText
                        }
                        self.parent.onTextChanged?()
                    }
                }
            }

            if parent.allowRescan {
                host?.resetPresentation()
            }
        }
    }
}
