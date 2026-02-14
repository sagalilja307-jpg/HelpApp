import Foundation
import SwiftData
#if canImport(CoreLocation)
import CoreLocation
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
    @available(iOS, deprecated: 26.0, message: "Use MapKit MKReverseGeocodingRequest")
    private let geocoder: CLGeocoder
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    #endif
    
    // Coarse rounding: 2 decimals ≈ 1.1 km
    static let coordinatePrecision: Double = 2
    static let fallbackMaxAge: TimeInterval = 30 * 60 // 30 minutes
    static let locationTimeout: TimeInterval = 15 // seconds
    
    init(memoryService: MemoryService, nowProvider: @escaping () -> Date = Date.init) {
        self.memoryService = memoryService
        self.modelContext = nil
        self.nowProvider = nowProvider
        #if canImport(CoreLocation)
        self.locationManager = CLLocationManager()
        self.geocoder = CLGeocoder()
        #endif
        super.init()
        #if canImport(CoreLocation)
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        #endif
    }
    
    init(context: ModelContext, nowProvider: @escaping () -> Date = Date.init) {
        self.memoryService = nil
        self.modelContext = context
        self.nowProvider = nowProvider
        #if canImport(CoreLocation)
        self.locationManager = CLLocationManager()
        self.geocoder = CLGeocoder()
        #endif
        super.init()
        #if canImport(CoreLocation)
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
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
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            // Try fallback
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
            // Try fallback on any location error
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
        
        let results = try context.fetch(descriptor)
        return results.first
    }
    
    // MARK: - Private Helpers
    
    #if canImport(CoreLocation)
    private func requestLocation() async throws -> CLLocation {
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()
            
            // Timeout after configured seconds
            Task {
                try? await Task.sleep(for: .seconds(Self.locationTimeout))
                if let cont = self.locationContinuation {
                    self.locationContinuation = nil
                    cont.resume(throwing: LocationError.timeout)
                }
            }
        }
    }
    
    private func createSnapshot(from location: CLLocation) async throws -> IndexedLocationSnapshot {
        let roundedLat = Self.roundCoordinate(location.coordinate.latitude)
        let roundedLon = Self.roundCoordinate(location.coordinate.longitude)
        
        let placeLabel = await reverseGeocode(location: location) ?? "Okänd plats"
        let now = nowProvider()
        
        // Create bucket-based ID for 15-minute intervals
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
        
        // Check for existing snapshot with same ID
        let existingDescriptor = FetchDescriptor<IndexedLocationSnapshot>(
            predicate: #Predicate { $0.id == snapshotId }
        )
        let existing = try context.fetch(existingDescriptor)
        
        if let existingSnapshot = existing.first {
            existingSnapshot.title = title
            existingSnapshot.bodySnippet = bodySnippet
            existingSnapshot.accuracyMeters = location.horizontalAccuracy
            existingSnapshot.placeLabel = placeLabel
            existingSnapshot.updatedAt = now
            try context.save()
            return existingSnapshot
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
    
    private func reverseGeocode(location: CLLocation) async -> String? {
        do {
            if #available(iOS 26.0, *) {
                // TODO: Migrate to MKReverseGeocodingRequest when iOS 26 is released
            }
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            
            // Build place label from available data
            var parts: [String] = []
            if let name = placemark.name { parts.append(name) }
            if let locality = placemark.locality, !parts.contains(locality) { parts.append(locality) }
            if let subLocality = placemark.subLocality, !parts.contains(subLocality) { parts.append(subLocality) }
            
            return parts.isEmpty ? placemark.locality : parts.prefix(2).joined(separator: ", ")
        } catch {
            return nil
        }
    }
    
    static func roundCoordinate(_ value: Double) -> Double {
        let multiplier = pow(10, coordinatePrecision)
        return (value * multiplier).rounded() / multiplier
    }
    
    private func buildBodySnippet(placeLabel: String, accuracy: Double, timestamp: Date) -> String {
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
    #endif
}

// MARK: - CLLocationManagerDelegate

#if canImport(CoreLocation)
extension LocationSnapshotService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(returning: location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(throwing: LocationError.locationUnavailable)
    }
}
#endif
