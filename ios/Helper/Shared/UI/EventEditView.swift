// EventEditView.swift
// SwiftUI wrapper for EKEventEditViewController

import SwiftUI
import EventKitUI

/// A SwiftUI-compatible wrapper for Apple's native calendar event editor.
public struct EventEditView: UIViewControllerRepresentable {
    public typealias UIViewControllerType = EKEventEditViewController

    private let event: EKEvent?
    private let store: EKEventStore
    private let onComplete: (Result<Void, Error>) -> Void

    /// Creates an event editing view using EventKit.
    /// - Parameters:
    ///   - event: Optional existing EKEvent to edit.
    ///   - store: The event store used to manage calendar data.
    ///   - onComplete: Callback when the editor finishes (with success or error).
    public init(event: EKEvent?, store: EKEventStore, onComplete: @escaping (Result<Void, Error>) -> Void) {
        self.event = event
        self.store = store
        self.onComplete = onComplete
    }

    public func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = store
        vc.editViewDelegate = context.coordinator
        if let event = event {
            vc.event = event
        }
        return vc
    }

    public func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {
        // No dynamic updates needed
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    /// Handles delegation from EKEventEditViewController
    public final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let onComplete: (Result<Void, Error>) -> Void

        init(onComplete: @escaping (Result<Void, Error>) -> Void) {
            self.onComplete = onComplete
        }

        public func eventEditViewController(_ controller: EKEventEditViewController,
                                            didCompleteWith action: EKEventEditViewAction) {
            defer { controller.dismiss(animated: true) }

            switch action {
            case .canceled:
                onComplete(.failure(NSError(domain: "UserCancelled", code: 0, userInfo: nil)))
            case .saved:
                onComplete(.success(()))
            case .deleted:
                onComplete(.success(()))
            @unknown default:
                onComplete(.failure(NSError(domain: "UnknownAction", code: -1, userInfo: nil)))
            }
        }
    }
}
