import Foundation
import SwiftData

#if canImport(CoreLocation)
import CoreLocation
#endif

#if canImport(MapKit)
import MapKit
#endif

// MARK: - Protocol

protocol LocationSnapshoting: Sendable {
    func captureSnapshot() async throws -> LocationSnapshotResult
    func lastSnapshot(maxAge: TimeInterval) throws -> IndexedLocationSnapshot?
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
        case geocodingFailed
        case timeout

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Platsåtkomst saknas."
            case .locationUnavailable:
                return "Kunde inte hämta plats."
            case .geocodingFailed:
                return "Kunde inte identifiera platsnamn."
            case .timeout:
                return "Tidsgräns för platsförfrågan uppnåddes."
            }
        }
    }

    private let memoryService: MemoryService?
    private let modelContext: ModelContext?
    private let nowProvider: () -> Date

    #if canImport(CoreLocation)
    private let locationManager: CLLocationManager
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    #endif

    static let coordinatePrecision: Double = 2
    static let fallbackMaxAge: TimeInterval = 30 * 60
    static let locationTimeout: TimeInterval = 15

    // MARK: - Init

    init(memoryService: MemoryService,
         nowProvider: @escaping () -> Date = Date.init) {

        self.memoryService = memoryService
        self.modelContext = nil
        self.nowProvider = nowProvider

        #if canImport(CoreLocation)
        self.locationManager = CLLocationManager()
        #endif

        super.init()

        #if canImport(CoreLocation)
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        #endif
    }

    init(context: ModelContext,
         nowProvider: @escaping () -> Date = Date.init) {

        self.memoryService = nil
        self.modelContext = context
        self.nowProvider = nowProvider

        #if canImport(CoreLocation)
        self.locationManager = CLLocationManager()
        #endif

        super.init()

        #if canImport(CoreLocation)
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        #endif
    }

    private func context() -> ModelContext {
        if let modelContext { return modelContext }
        return memoryService!.context()
    }

    // MARK: - Public API

    func captureSnapshot() async throws -> LocationSnapshotResult {

        #if canImport(CoreLocation)

        let status = locationManager.authorizationStatus

        guard status == .authorizedWhenInUse ||
              status == .authorizedAlways else {

            if let fallback = try lastSnapshot(maxAge: Self.fallbackMaxAge) {
                return LocationSnapshotResult(snapshot: fallback, fallbackUsed: true)
            }

            throw LocationError.notAuthorized
        }

        do {
            let location = try await requestLocation()
            let snapshot = try await createSnapshot(from: location)
            return LocationSnapshotResult(snapshot: snapshot, fallbackUsed: false)

        } catch {
            if let fallback = try lastSnapshot(maxAge: Self.fallbackMaxAge) {
                return LocationSnapshotResult(snapshot: fallback, fallbackUsed: true)
            }
            throw error
        }

        #else
        throw LocationError.locationUnavailable
        #endif
    }

    func lastSnapshot(maxAge: TimeInterval) throws -> IndexedLocationSnapshot? {
        let context = context()
        let cutoff = nowProvider().addingTimeInterval(-maxAge)

        var descriptor = FetchDescriptor<IndexedLocationSnapshot>(
            predicate: #Predicate { $0.observedAt >= cutoff },
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )

        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

#if canImport(CoreLocation)
private extension LocationSnapshotService {

    func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in

            locationContinuation = continuation
            locationManager.requestLocation()

            Task {
                try? await Task.sleep(for: .seconds(Self.locationTimeout))

                if let continuation = self.locationContinuation {
                    self.locationContinuation = nil
                    continuation.resume(throwing: LocationError.timeout)
                }
            }
        }
    }

    func createSnapshot(from location: CLLocation) async throws -> IndexedLocationSnapshot {

        let roundedLat = Self.roundCoordinate(location.coordinate.latitude)
        let roundedLon = Self.roundCoordinate(location.coordinate.longitude)

        let placeLabel = await reverseGeocode(location: location) ?? "Okänd plats"
        let now = nowProvider()

        let timeBucket = Int(location.timestamp.timeIntervalSince1970 / (15 * 60))
        let latBucket = String(format: "%.2f", roundedLat)
        let lonBucket = String(format: "%.2f", roundedLon)
        let snapshotId = "location:\(latBucket):\(lonBucket):\(timeBucket)"

        let title = placeLabel.isEmpty ? "Ungefärlig position" : "Nära \(placeLabel)"
        let bodySnippet = buildBodySnippet(
            placeLabel: placeLabel,
            accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )

        let context = context()

        let existingDescriptor = FetchDescriptor<IndexedLocationSnapshot>(
            predicate: #Predicate { $0.id == snapshotId }
        )

        if let existing = try context.fetch(existingDescriptor).first {
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

    // MARK: - Reverse Geocoding
    func reverseGeocode(location: CLLocation) async -> String? {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            
            guard let placemark = placemarks.first else {
                return nil
            }

            var parts: [String] = []

            // Försök hämta namn från placemarken
            if let name = placemark.name {
                parts.append(name)
            }

            // Lägg till stad/kommun
            if let city = placemark.locality,
               !parts.contains(city) {
                parts.append(city)
            }

            // Lägg till stadsdel/område
            if let subArea = placemark.subLocality,
               !parts.contains(subArea) {
                parts.append(subArea)
            }

            return parts.isEmpty
                ? placemark.locality
                : parts.prefix(2).joined(separator: ", ")

        } catch {
            return nil
        }
    }

    static func roundCoordinate(_ value: Double) -> Double {
        let multiplier = pow(10, coordinatePrecision)
        return (value * multiplier).rounded() / multiplier
    }

    func buildBodySnippet(placeLabel: String,
                          accuracy: Double,
                          timestamp: Date) -> String {

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
#endif

#if canImport(CoreLocation)
extension LocationSnapshotService: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {

        guard let location = locations.last,
              let continuation = locationContinuation else { return }

        locationContinuation = nil
        continuation.resume(returning: location)
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {

        guard let continuation = locationContinuation else { return }

        locationContinuation = nil
        continuation.resume(throwing: LocationError.locationUnavailable)
    }
}
#endif

