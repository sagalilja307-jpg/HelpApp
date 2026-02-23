import SwiftData
import Foundation

@Model
public final class RawEvent {
    
    // MARK: - Core fields
    
    @Attribute(.unique) public var id: String
    public var source: String
    public var timestamp: Date
    public var payloadJSON: String
    public var createdAt: Date
    public var text: String?  // 🆕 valfritt textfält som kan användas direkt

    // MARK: - Relationships
    
    @Relationship(deleteRule: .cascade, inverse: \ClusterItem.event)
    public var clusterItems: [ClusterItem] = []

    // MARK: - Init

    public init(
        id: String,
        source: String,
        timestamp: Date,
        payloadJSON: String,
        text: String? = nil,
        createdAt: Date = DateService.shared.now()
    ) {
        self.id = id
        self.source = source
        self.timestamp = timestamp
        self.payloadJSON = payloadJSON
        self.text = text
        self.createdAt = createdAt
    }
}
