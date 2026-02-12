import Foundation
import SwiftData

@Model
public final class DecisionLogEntry {

    /// Stable unique identifier for this decision
    @Attribute(.unique)
    public var decisionId: String

    /// What the system decided to do
    /// Examples: "no_action", "suggested", "suppressed", "scheduled"
    public var action: String

    /// JSON describing *why* this decision was made
    /// (rules fired, confidence, thresholds, etc.)
    public var reasonJSON: String

    /// Optional JSON describing which memory entries were used
    /// (raw events, patterns, clusters)
    public var usedMemoryJSON: String?

    /// When the decision was created
    public var createdAt: Date

    public init(
        decisionId: String,
        action: String,
        reasonJSON: String,
        usedMemoryJSON: String? = nil,
        createdAt: Date = .now
    ) {
        self.decisionId = decisionId
        self.action = action
        self.reasonJSON = reasonJSON
        self.usedMemoryJSON = usedMemoryJSON
        self.createdAt = createdAt
    }
}
