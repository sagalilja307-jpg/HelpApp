import Foundation
import SwiftData

@Model
public final class IndexedLocationSnapshot {
    @Attribute(.unique)
    public var id: String

    public var title: String
    public var bodySnippet: String
    public var roundedLat: Double
    public var roundedLon: Double
    public var accuracyMeters: Double
    public var placeLabel: String
    public var observedAt: Date
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        bodySnippet: String,
        roundedLat: Double,
        roundedLon: Double,
        accuracyMeters: Double,
        placeLabel: String,
        observedAt: Date,
        createdAt: Date = DateService.shared.now(),
        updatedAt: Date = DateService.shared.now()
    ) {
        self.id = id
        self.title = title
        self.bodySnippet = bodySnippet
        self.roundedLat = roundedLat
        self.roundedLon = roundedLon
        self.accuracyMeters = accuracyMeters
        self.placeLabel = placeLabel
        self.observedAt = observedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
