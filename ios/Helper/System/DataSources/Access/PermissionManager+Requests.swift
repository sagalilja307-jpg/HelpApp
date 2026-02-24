import Foundation
import EventKit
import AVFoundation
import UserNotifications

#if canImport(Contacts)
import Contacts
#endif

#if canImport(Photos)
@preconcurrency import Photos
#endif

extension PermissionManager {

    // MARK: - Calendar

    func requestCalendarAccess() async throws -> AppPermissionStatus {
        if #available(iOS 17.0, *) {
            let granted = try await eventStore.requestFullAccessToEvents()
            return granted ? .granted : .denied
        } else {
            let granted = try await eventStore.requestAccess(to: .event)
            return granted ? .granted : .denied
        }
    }

    // MARK: - Reminder

    func requestReminderAccess() async throws -> AppPermissionStatus {
        if #available(iOS 17.0, *) {
            let granted = try await eventStore.requestFullAccessToReminders()
            return granted ? .granted : .denied
        } else {
            let granted = try await eventStore.requestAccess(to: .reminder)
            return granted ? .granted : .denied
        }
    }

    // MARK: - Notifications

    func requestNotificationAccess() async throws {
        _ = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Camera

    func requestCameraAccess() async throws {
        _ = await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - Contacts

    func requestContactsAccess() async throws {
        #if canImport(Contacts)
        _ = try await CNContactStore().requestAccess(for: .contacts)
        #endif
    }

    // MARK: - Photos

    func requestPhotosAccess() async throws -> AppPermissionStatus {
        #if canImport(Photos)
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return mapPhotosStatus(newStatus)
        #else
        return .denied
        #endif
    }

    // MARK: - Location (Deterministic)

    func requestLocationAccess() async -> AppPermissionStatus {
        let current = locationManager.authorizationStatus

        if current != .notDetermined {
            return mapLocationStatus(current)
        }

        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }
}
