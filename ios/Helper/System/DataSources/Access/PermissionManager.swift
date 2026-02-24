import Foundation
import EventKit
import AVFoundation
import UserNotifications

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
    private var locationContinuation: CheckedContinuation<AppPermissionStatus, Never>?

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
            return mapLocationStatus(locationManager.authorizationStatus)
        }
    }

    // MARK: - REQUEST ENTRY POINT

    func requestAccess(for type: AppPermissionType) async throws -> AppPermissionStatus {
        switch type {

        case .calendar:
            return try await requestCalendarAccess()

        case .reminder:
            return try await requestReminderAccess()

        case .notification:
            try await requestNotificationAccess()
            return await status(for: .notification)

        case .camera:
            try await requestCameraAccess()
            return await status(for: .camera)

        case .contacts:
            try await requestContactsAccess()
            return await status(for: .contacts)

        case .photos:
            return try await requestPhotosAccess()

        case .location:
            return await requestLocationAccess()
        }
    }

    // MARK: - Calendar

    private func requestCalendarAccess() async throws -> AppPermissionStatus {
        if #available(iOS 17.0, *) {
            let granted = try await eventStore.requestFullAccessToEvents()
            return granted ? .granted : .denied
        } else {
            let granted = try await eventStore.requestAccess(to: .event)
            return granted ? .granted : .denied
        }
    }

    // MARK: - Reminder

    private func requestReminderAccess() async throws -> AppPermissionStatus {
        if #available(iOS 17.0, *) {
            let granted = try await eventStore.requestFullAccessToReminders()
            return granted ? .granted : .denied
        } else {
            let granted = try await eventStore.requestAccess(to: .reminder)
            return granted ? .granted : .denied
        }
    }

    // MARK: - Notifications

    private func requestNotificationAccess() async throws {
        _ = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Camera

    private func requestCameraAccess() async throws {
        _ = await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - Contacts

    private func requestContactsAccess() async throws {
        #if canImport(Contacts)
        _ = try await CNContactStore().requestAccess(for: .contacts)
        #endif
    }

    // MARK: - Photos (MAX ACCESS ONLY)

    private func requestPhotosAccess() async throws -> AppPermissionStatus {
        #if canImport(PhotoKit)
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return mapPhotosStatus(newStatus)
        #else
        return .denied
        #endif
    }

    // MARK: - Location (Deterministic)

    private func requestLocationAccess() async -> AppPermissionStatus {
        let current = locationManager.authorizationStatus

        if current != .notDetermined {
            return mapLocationStatus(current)
        }

        return await withCheckedContinuation { continuation in
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

    private func photosPermissionStatus() -> AppPermissionStatus {
        #if canImport(PhotoKit)
        return mapPhotosStatus(
            PHPhotoLibrary.authorizationStatus(for: .readWrite)
        )
        #else
        return .denied
        #endif
    }

    private func mapPhotosStatus(_ status: PHAuthorizationStatus) -> AppPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .granted
        case .limited:
            return .denied   // MAX ACCESS ONLY
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
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
    private func contactsPermissionStatus() -> AppPermissionStatus {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .limited:
            return .granted
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

            let status = mapLocationStatus(manager.authorizationStatus)
            continuation.resume(returning: status)
            locationContinuation = nil
        }
    }
}