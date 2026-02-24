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

#if canImport(CoreLocation)
@preconcurrency import CoreLocation
#endif

extension PermissionManager {

    // MARK: - Status Mapping

    func mapEventKitStatus(_ status: EKAuthorizationStatus) -> AppPermissionStatus {
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

    func mapNotificationStatus(_ status: UNAuthorizationStatus) -> AppPermissionStatus {
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

    func mapCameraStatus(_ status: AVAuthorizationStatus) -> AppPermissionStatus {
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

    func photosPermissionStatus() -> AppPermissionStatus {
        #if canImport(Photos)
        return mapPhotosStatus(
            PHPhotoLibrary.authorizationStatus(for: .readWrite)
        )
        #else
        return .denied
        #endif
    }

    #if canImport(Photos)
    func mapPhotosStatus(_ status: PHAuthorizationStatus) -> AppPermissionStatus {
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
    #else
    func mapPhotosStatus(_ status: Any) -> AppPermissionStatus { return .granted }
    #endif

    #if canImport(CoreLocation)
    func mapLocationStatus(_ status: CLAuthorizationStatus) -> AppPermissionStatus {
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
    func contactsPermissionStatus() -> AppPermissionStatus {
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
