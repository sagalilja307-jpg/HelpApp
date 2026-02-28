import Foundation
import EventKit
import AVFoundation
import UserNotifications
#if canImport(HealthKit)
@preconcurrency import HealthKit
#endif

#if canImport(CoreLocation)
@preconcurrency import CoreLocation
#endif

@MainActor
final class PermissionManager: NSObject {

    static let shared = PermissionManager()

    let eventStore = EKEventStore()
    let locationManager = CLLocationManager()
    var locationContinuation: CheckedContinuation<AppPermissionStatus, Never>?
#if canImport(HealthKit)
    let healthStore = HKHealthStore()
#endif

    private override init() {
        super.init()
        locationManager.delegate = self
    }

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
        case .healthActivity, .healthSleep, .healthMental, .healthVitals:
            return await healthPermissionStatus(for: type)
        }
    }

    // MARK: - REQUEST ENTRY POINT

    func requestAccess(for type: AppPermissionType) async throws -> AppPermissionStatus {
        let op = "PermissionsRequestAccess"
        DataSourceDebug.start(op)
        do {
            let status: AppPermissionStatus
            switch type {

            case .calendar:
                status = try await requestCalendarAccess()

            case .reminder:
                status = try await requestReminderAccess()

            case .notification:
                try await requestNotificationAccess()
                status = await self.status(for: .notification)

            case .camera:
                try await requestCameraAccess()
                status = await self.status(for: .camera)

            case .contacts:
                try await requestContactsAccess()
                status = await self.status(for: .contacts)

            case .photos:
                status = try await requestPhotosAccess()

            case .location:
                status = await requestLocationAccess()
            case .healthActivity, .healthSleep, .healthMental, .healthVitals:
                status = try await requestHealthAccess(for: type)
            }
            DataSourceDebug.success(op)
            return status
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }
}
