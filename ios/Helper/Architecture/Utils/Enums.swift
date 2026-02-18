import Foundation
import SwiftData

public enum RequiresPrep: String, Codable, Sendable {
    case `true`
    case `false`
    case unknown
}

public enum ClusterStatus: String, Codable, Sendable {
    case proposed
    case active
    case waitingForResponse   // 🆕 NY STATUS
    case archived
}

// MARK: - Actor (model-friendly wrapper)

/// En wrapper runt `Actor` enum för att stödja SwiftData.
@Model
public final class ActorRaw {
    public var value: String

    public init(value: String) {
        self.value = value
    }

    public var toEnum: Actor? {
        Actor(rawValue: value)
    }
}
