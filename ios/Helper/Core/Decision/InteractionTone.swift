import Foundation

/// Describes how the system should communicate.
public enum InteractionTone: String, Codable, Sendable {
    case neutral
    case gentle
    case direct
}
