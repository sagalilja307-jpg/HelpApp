import Foundation

extension LocationCollectorService {

    // MARK: - Mapping

    nonisolated static func mapToUnifiedItem(_ snapshot: IndexedLocationSnapshot) -> UnifiedItemDTO {
        UnifiedItemDTO(
            id: snapshot.id,
            source: "location",
            type: .location,
            title: snapshot.title,
            body: snapshot.bodySnippet,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt,
            startAt: snapshot.observedAt,
            endAt: nil,
            dueAt: nil,
            status: [
                "lat": AnyCodable(snapshot.roundedLat),
                "lon": AnyCodable(snapshot.roundedLon),
                "accuracy": AnyCodable(snapshot.accuracyMeters),
                "place_label": AnyCodable(snapshot.placeLabel)
            ]
        )
    }

    nonisolated static func makeEntry(_ snapshot: IndexedLocationSnapshot) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(),
            source: .location,
            title: snapshot.title,
            body: snapshot.bodySnippet,
            date: snapshot.observedAt,
            latitude: snapshot.roundedLat,
            longitude: snapshot.roundedLon
        )
    }
}
