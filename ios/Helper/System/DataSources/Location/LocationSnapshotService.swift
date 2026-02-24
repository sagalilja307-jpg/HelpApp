import Foundation
import SwiftData
#if canImport(CoreLocation)
@preconcurrency import CoreLocation
#endif

// MARK: - Protocol

protocol LocationSnapshoting: Sendable {
    @MainActor
    func captureSnapshot(
        in context: ModelContext
    ) async throws -> LocationSnapshotResult

    func lastSnapshot(
        maxAge: TimeInterval,
        in context: ModelContext
    ) throws -> IndexedLocationSnapshot?
}

struct LocationSnapshotResult: Sendable {
    let snapshot: IndexedLocationSnapshot
    let fallbackUsed: Bool
}

// MARK: - Service

final class LocationSnapshotService: NSObject, LocationSnapshoting {

    enum LocationError: Error, LocalizedError {
        case notAuthorized
        case locationUnavailable
        case timeout

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Platsåtkomst saknas."
            case .locationUnavailable: return "Kunde inte hämta plats."
            case .timeout: return "Tidsgräns för platsförfrågan uppnåddes."
            }
        }
    }

    let nowProvider: () -> Date

    #if canImport(CoreLocation)
    let locationManager: CLLocationManager
    let geocoder: CLGeocoder
    var locationContinuation: CheckedContinuation<CLLocation, Error>?
    #endif

    static let coordinatePrecision: Double = 2
    static let fallbackMaxAge: TimeInterval = 30 * 60
    static let locationTimeout: TimeInterval = 15

    init(
        nowProvider: @escaping () -> Date = DateService.shared.now
    ) {
        self.nowProvider = nowProvider
        #if canImport(CoreLocation)
        self.locationManager = CLLocationManager()
        self.geocoder = CLGeocoder()
        #endif
        super.init()
        #if canImport(CoreLocation)
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        #endif
    }

    // MARK: - Public

    @MainActor
    func captureSnapshot(
        in context: ModelContext
    ) async throws -> LocationSnapshotResult {
        let op = "LocationCaptureSnapshot"
        DataSourceDebug.start(op)

        #if canImport(CoreLocation)
        do {
            let status = locationManager.authorizationStatus

            guard status == .authorizedWhenInUse ||
                  status == .authorizedAlways else {

                if let fallback = try lastSnapshot(
                    maxAge: Self.fallbackMaxAge,
                    in: context
                ) {
                    DataSourceDebug.success(op, count: 1)
                    return LocationSnapshotResult(
                        snapshot: fallback,
                        fallbackUsed: true
                    )
                }

                throw LocationError.notAuthorized
            }

            let location = try await requestLocation()
            let snapshot = try await createSnapshot(
                from: location,
                in: context
            )
            DataSourceDebug.success(op, count: 1)
            return LocationSnapshotResult(
                snapshot: snapshot,
                fallbackUsed: false
            )
        } catch {

            if let fallback = try lastSnapshot(
                maxAge: Self.fallbackMaxAge,
                in: context
            ) {
                DataSourceDebug.success(op, count: 1)
                return LocationSnapshotResult(
                    snapshot: fallback,
                    fallbackUsed: true
                )
            }

            DataSourceDebug.failure(op, error)
            throw error
        }

        #else
        DataSourceDebug.failure(op, LocationError.locationUnavailable)
        throw LocationError.locationUnavailable
        #endif
    }

    func lastSnapshot(
        maxAge: TimeInterval,
        in context: ModelContext
    ) throws -> IndexedLocationSnapshot? {

        let cutoff = nowProvider()
            .addingTimeInterval(-maxAge)

        var descriptor = FetchDescriptor<IndexedLocationSnapshot>(
            predicate: #Predicate { $0.observedAt >= cutoff },
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        return try context.fetch(descriptor).first
    }
}
