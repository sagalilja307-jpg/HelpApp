import SwiftData
import Foundation

@Model
public final class ClusterItem {
    @Attribute(.unique) public var id: UUID
    @Relationship public var cluster: Cluster
    @Relationship public var event: RawEvent
    public var addedAt: Date

    public init(cluster: Cluster, event: RawEvent, addedAt: Date = Date()) {
        self.id = UUID()
        self.cluster = cluster
        self.event = event
        self.addedAt = addedAt
    }

    public var timestamp: Date {
        event.timestamp
    }

    /// Extracts raw text from event payload, if available
    public var rawText: String {
        // Försök att läsa `rawText` från payloadJSON
        if let data = event.payloadJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["rawText"] as? String {
            return text
        }

        return "[okänt innehåll]"
    }
}
