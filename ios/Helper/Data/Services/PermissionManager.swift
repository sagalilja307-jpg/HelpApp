import Foundation
import EventKit
import AVFoundation
import UserNotifications
import Combine
#if canImport(Contacts)
import Contacts
#endif
#if canImport(PhotoKit)
import PhotoKit
#endif
#if canImport(CoreLocation)
import CoreLocation
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
final class PermissionManager {

    static let shared = PermissionManager()
    private init() {}

    private let eventStore = EKEventStore()

    // MARK: - Status

    func status(for type: AppPermissionType) async -> AppPermissionStatus {
        switch type {
        case .calendar:
            return mapEventKitStatus(EKEventStore.authorizationStatus(for: .event))
        case .reminder:
            return mapEventKitStatus(EKEventStore.authorizationStatus(for: .reminder))
        case .notification:
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            return mapNotificationStatus(settings.authorizationStatus)
        case .camera:
            return mapCameraStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .contacts:
            return contactsPermissionStatus()
        case .photos:
            return photosPermissionStatus()
        case .location:
            return locationPermissionStatus()
        }
    }

    // Synchronous convenience for non-concurrent callers. Note: notification status defaults to .notDetermined here.
    func statusSync(for type: AppPermissionType) -> AppPermissionStatus {
        switch type {
        case .calendar:
            return mapEventKitStatus(EKEventStore.authorizationStatus(for: .event))
        case .reminder:
            return mapEventKitStatus(EKEventStore.authorizationStatus(for: .reminder))
        case .notification:
            // Cannot synchronously fetch UNNotificationSettings on newer SDKs.
            return .notDetermined
        case .camera:
            return mapCameraStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .contacts:
            return contactsPermissionStatus()
        case .photos:
            return photosPermissionStatus()
        case .location:
            return locationPermissionStatus()
        }
    }

    // MARK: - Requests

    func requestCalendarAccess() async throws {
        if #available(iOS 17.0, macOS 14.0, *) {
            _ = try await eventStore.requestFullAccessToEvents()
        } else {
            try await eventStore.requestAccess(to: .event)
        }
    }

    func requestReminderAccess() async throws {
        if #available(iOS 17.0, macOS 14.0, *) {
            _ = try await eventStore.requestFullAccessToReminders()
        } else {
            try await eventStore.requestAccess(to: .reminder)
        }
    }

    func requestNotificationAccess() async throws {
        _ = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    func requestCameraAccess() async throws {
        _ = await AVCaptureDevice.requestAccess(for: .video)
    }

    func requestContactsAccess() async throws {
        #if canImport(Contacts)
        _ = try await CNContactStore().requestAccess(for: .contacts)
        #endif
    }

    func requestPhotosAccess() async throws {
        #if canImport(PhotoKit)
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        #endif
    }

    func requestLocationAccess() async throws {
        #if canImport(CoreLocation)
        let locationManager = CLLocationManager()
        locationManager.requestWhenInUseAuthorization()
        // Allow time for the system dialog to process
        try await Task.sleep(for: .milliseconds(100))
        #endif
    }

    // MARK: - Private Mapping Helpers

    private func mapEventKitStatus(_ status: EKAuthorizationStatus) -> AppPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized, .fullAccess:
            return .granted
        case .denied, .restricted, .writeOnly:
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
        return mapContactsStatus(CNContactStore.authorizationStatus(for: .contacts))
        #else
        return .denied
        #endif
    }

    private func photosPermissionStatus() -> AppPermissionStatus {
        #if canImport(PhotoKit)
        return mapPhotosStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        #else
        return .denied
        #endif
    }

    private func locationPermissionStatus() -> AppPermissionStatus {
        #if canImport(CoreLocation)
        return mapLocationStatus(CLLocationManager.authorizationStatus())
        #else
        return .denied
        #endif
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
    private func mapContactsStatus(
        _ status: CNAuthorizationStatus
    ) -> AppPermissionStatus {
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
    private func mapPhotosStatus(
        _ status: PHAuthorizationStatus
    ) -> AppPermissionStatus {
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

// MARK: - CalendarSyncManager

public final class CalendarSyncManager: ObservableObject {

    public enum PermissionState {
        case unknown
        case denied
        case authorized
    }

    @Published public private(set) var permission: PermissionState = .unknown

    private let store: EKEventStore
    private var cancellables = Set<AnyCancellable>()

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
        refreshAuthorizationStatus()

        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Permission Handling

    public func refreshAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .notDetermined:
            permission = .unknown
        case .denied, .restricted:
            permission = .denied
        case .authorized, .fullAccess:
            permission = .authorized
        case .writeOnly:
            permission = .denied
        @unknown default:
            permission = .unknown
        }
    }

    public func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async {
                    self.refreshAuthorizationStatus()
                    completion(granted)
                }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async {
                    self.refreshAuthorizationStatus()
                    completion(granted)
                }
            }
        }
    }
}
