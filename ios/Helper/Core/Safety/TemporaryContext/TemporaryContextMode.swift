import Foundation

/// Describes the user's current capacity / intent.
/// This is temporary and user-controlled.
public enum TemporaryContextMode: String, Codable, Sendable {
    case normal
    case lowEnergy
    case overwhelmed
    case focused
    case supportive
}
