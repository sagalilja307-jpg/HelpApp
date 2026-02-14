import Foundation
import SwiftData
#if canImport(CoreLocation)
import CoreLocation
#endif

// MARK: - Protocol

protocol LocationSnapshoting: Sendable {
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

    private let nowProvider: () -> Date

    #if canImport(CoreLocation)
    private let locationManager: CLLocationManager
    private let geocoder: CLGeocoder
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    #endif

    static let coordinatePrecision: Double = 2
    static let fallbackMaxAge: TimeInterval = 30 * 60
    static let locationTimeout: TimeInterval = 15

    init(
        nowProvider: @escaping () -> Date = Date.init
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

    func captureSnapshot(
        in context: ModelContext
    ) async throws -> LocationSnapshotResult {

        #if canImport(CoreLocation)

        let status = locationManager.authorizationStatus

        guard status == .authorizedWhenInUse ||
              status == .authorizedAlways else {

            if let fallback = try lastSnapshot(
                maxAge: Self.fallbackMaxAge,
                in: context
            ) {
                return LocationSnapshotResult(
                    snapshot: fallback,
                    fallbackUsed: true
                )
            }

            throw LocationError.notAuthorized
        }

        do {
            let location = try await requestLocation()
            let snapshot = try await createSnapshot(
                from: location,
                in: context
            )
            return LocationSnapshotResult(
                snapshot: snapshot,
                fallbackUsed: false
            )
        } catch {

            if let fallback = try lastSnapshot(
                maxAge: Self.fallbackMaxAge,
                in: context
            ) {
                return LocationSnapshotResult(
                    snapshot: fallback,
                    fallbackUsed: true
                )
            }

            throw error
        }

        #else
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

    // MARK: - Private

    #if canImport(CoreLocation)

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()

            Task {
                try? await Task.sleep(
                    for: .seconds(Self.locationTimeout)
                )

                if let cont = locationContinuation {
                    locationContinuation = nil
                    cont.resume(throwing: LocationError.timeout)
                }
            }
        }
    }

    private func createSnapshot(
        from location: CLLocation,
        in context: ModelContext
    ) async throws -> IndexedLocationSnapshot {

        let roundedLat = Self.roundCoordinate(location.coordinate.latitude)
        let roundedLon = Self.roundCoordinate(location.coordinate.longitude)

        let placeLabel =
            await reverseGeocode(location: location) ?? "Okänd plats"

        let now = nowProvider()

        let timeBucket =
            Int(location.timestamp.timeIntervalSince1970 / (15 * 60))

        let snapshotId =
            "location:\(roundedLat):\(roundedLon):\(timeBucket)"

        let title =
            placeLabel.isEmpty
            ? "Ungefärlig position"
            : "Nära \(placeLabel)"

        let bodySnippet = buildBodySnippet(
            placeLabel: placeLabel,
            accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )

        var descriptor = FetchDescriptor<IndexedLocationSnapshot>(
            predicate: #Predicate { $0.id == snapshotId }
        )

        if let existing = try context.fetch(descriptor).first {

            existing.title = title
            existing.bodySnippet = bodySnippet
            existing.accuracyMeters = location.horizontalAccuracy
            existing.placeLabel = placeLabel
            existing.updatedAt = now

            try context.save()
            return existing
        }

        let snapshot = IndexedLocationSnapshot(
            id: snapshotId,
            title: title,
            bodySnippet: bodySnippet,
            roundedLat: roundedLat,
            roundedLon: roundedLon,
            accuracyMeters: location.horizontalAccuracy,
            placeLabel: placeLabel,
            observedAt: location.timestamp,
            createdAt: now,
            updatedAt: now
        )

        context.insert(snapshot)
        try context.save()

        return snapshot
    }

    #endif

    static func roundCoordinate(_ value: Double) -> Double {
        let multiplier = pow(10, coordinatePrecision)
        return (value * multiplier).rounded() / multiplier
    }

    private func buildBodySnippet(
        placeLabel: String,
        accuracy: Double,
        timestamp: Date
    ) -> String {

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "HH:mm"

        let timeString = formatter.string(from: timestamp)

        let accuracyText: String

        if accuracy < 100 {
            accuracyText = "ca \(Int(accuracy)) m"
        } else if accuracy < 1000 {
            accuracyText = "ca \(Int(accuracy / 100) * 100) m"
        } else {
            accuracyText = "ca \(Int(accuracy / 1000)) km"
        }

        if placeLabel.isEmpty {
            return "Ungefärlig plats kl \(timeString) (noggrannhet: \(accuracyText))"
        }

        return "Nära \(placeLabel) kl \(timeString) (noggrannhet: \(accuracyText))"
    }
}

#if canImport(CoreLocation)
extension LocationSnapshotService: CLLocationManagerDelegate {

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last,
              let continuation = locationContinuation else { return }

        locationContinuation = nil
        continuation.resume(returning: location)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(
            throwing: LocationError.locationUnavailable
        )
    }
}
#endif
