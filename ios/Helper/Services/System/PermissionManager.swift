import Foundation
import EventKit
import AVFoundation
import UserNotifications
import Combine

#if canImport(Contacts)
import Contacts
#endif

#if canImport(PhotoKit)
@preconcurrency import PhotoKit
#endif

#if canImport(CoreLocation)
@preconcurrency import CoreLocation
#endif

// MARK: - App Permission Types & Status

enum AppPermissionType {
    case calendar
    case reminder
    case notification
    case camera
    case contacts
    case photos
    case location
}

enum AppPermissionStatus {
    case notDetermined
    case granted
    case denied
}

// MARK: - PermissionManager

@MainActor
final class PermissionManager: NSObject {

    static let shared = PermissionManager()
    private override init() {
        super.init()
        locationManager.delegate = self
    }

    private let eventStore = EKEventStore()
    private let locationManager = CLLocationManager()

    private var locationContinuation: CheckedContinuation<Void, Error>?

    // MARK: - STATUS

    func status(for type: AppPermissionType) async -> AppPermissionStatus {
        switch type {

        case .calendar:
            return mapEventKitStatus(
                EKEventStore.authorizationStatus(for: .event)
            )

        case .reminder:
            return mapEventKitStatus(
                EKEventStore.authorizationStatus(for: .reminder)
            )

        case .notification:
            let settings = await UNUserNotificationCenter.current()
                .notificationSettings()
            return mapNotificationStatus(settings.authorizationStatus)

        case .camera:
            return mapCameraStatus(
                AVCaptureDevice.authorizationStatus(for: .video)
            )

        case .contacts:
            return contactsPermissionStatus()

        case .photos:
            return photosPermissionStatus()

        case .location:
            return locationPermissionStatus()
        }
    }

    // MARK: - REQUESTS

    func requestAccess(for type: AppPermissionType) async throws {
        switch type {

        case .calendar:
            try await requestCalendarAccess()

        case .reminder:
            try await requestReminderAccess()

        case .notification:
            try await requestNotificationAccess()

        case .camera:
            try await requestCameraAccess()

        case .contacts:
            try await requestContactsAccess()

        case .photos:
            _ = try await requestPhotosAccess()

        case .location:
            try await requestLocationAccess()
        }
    }

    // MARK: Calendar

    private func requestCalendarAccess() async throws {
        if #available(iOS 17.0, *) {
            _ = try await eventStore.requestFullAccessToEvents()
        } else {
            try await eventStore.requestAccess(to: .event)
        }
    }

    private func requestReminderAccess() async throws {
        if #available(iOS 17.0, *) {
            _ = try await eventStore.requestFullAccessToReminders()
        } else {
            try await eventStore.requestAccess(to: .reminder)
        }
    }

    // MARK: Notifications

    private func requestNotificationAccess() async throws {
        _ = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: Camera

    private func requestCameraAccess() async throws {
        _ = await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: Contacts

    private func requestContactsAccess() async throws {
        #if canImport(Contacts)
        _ = try await CNContactStore().requestAccess(for: .contacts)
        #endif
    }

    // MARK: Photos

    private func requestPhotosAccess() async throws -> AppPermissionStatus {
        #if canImport(PhotoKit)
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch current {
        case .authorized, .limited:
            return mapPhotosStatus(current)
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return mapPhotosStatus(newStatus)
        case .denied, .restricted:
            return mapPhotosStatus(current)
        @unknown default:
            return mapPhotosStatus(current)
        }
        #else
        return .denied
        #endif
    }

    // MARK: Location (Correct Async Implementation)

    private func requestLocationAccess() async throws {
        let current = locationManager.authorizationStatus
        guard current == .notDetermined else { return }

        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }

    // MARK: - Status Mapping

    private func mapEventKitStatus(_ status: EKAuthorizationStatus) -> AppPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized, .fullAccess, .writeOnly:
            return .granted
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private func mapNotificationStatus(_ status: UNAuthorizationStatus) -> AppPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private func mapCameraStatus(_ status: AVAuthorizationStatus) -> AppPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private func contactsPermissionStatus() -> AppPermissionStatus {
        #if canImport(Contacts)
        return mapContactsStatus(
            CNContactStore.authorizationStatus(for: .contacts)
        )
        #else
        return .denied
        #endif
    }

    private func photosPermissionStatus() -> AppPermissionStatus {
        #if canImport(PhotoKit)
        return mapPhotosStatus(
            PHPhotoLibrary.authorizationStatus(for: .readWrite)
        )
        #else
        return .denied
        #endif
    }

    private func locationPermissionStatus() -> AppPermissionStatus {
        mapLocationStatus(locationManager.authorizationStatus)
    }

    #if canImport(CoreLocation)
    private func mapLocationStatus(_ status: CLAuthorizationStatus) -> AppPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse:
            return .granted
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
    #endif

    #if canImport(Contacts)
    private func mapContactsStatus(_ status: CNAuthorizationStatus) -> AppPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized, .limited:
            return .granted
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
    #endif

    #if canImport(PhotoKit)
    private func mapPhotosStatus(_ status: PHAuthorizationStatus) -> AppPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized, .limited:
            return .granted
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
    #endif
}

// MARK: - CLLocationManagerDelegate

extension PermissionManager: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        Task { @MainActor in
            guard let continuation = locationContinuation else { return }

            let status = manager.authorizationStatus
            if status != .notDetermined {
                continuation.resume()
                locationContinuation = nil
            }
        }
    }
}
