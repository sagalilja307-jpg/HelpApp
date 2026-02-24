import Foundation
import SwiftData
#if canImport(CoreLocation)
@preconcurrency import CoreLocation
#endif

extension LocationSnapshotService {

    // MARK: - Helpers

    #if canImport(CoreLocation)

    func requestLocation() async throws -> CLLocation {
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

    func createSnapshot(
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

        let descriptor = FetchDescriptor<IndexedLocationSnapshot>(
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

    func buildBodySnippet(
        placeLabel: String,
        accuracy: Double,
        timestamp: Date
    ) -> String {

        let formatter = DateService.shared.dateFormatter(
            dateFormat: "HH:mm"
        )

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

    #if canImport(CoreLocation)
    func reverseGeocode(location: CLLocation) async -> String? {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }

            if let name = placemark.name, !name.isEmpty {
                return name
            }
            if let locality = placemark.locality {
                return locality
            }
            if let area = placemark.administrativeArea {
                return area
            }
            return nil
        } catch {
            return nil
        }
    }
    #endif
}
