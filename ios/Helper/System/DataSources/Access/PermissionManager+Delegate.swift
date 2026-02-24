import Foundation

#if canImport(CoreLocation)
@preconcurrency import CoreLocation
#endif

#if canImport(CoreLocation)

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

#endif
