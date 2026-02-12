import Foundation

/// Determines when a preference applies.
public enum PreferenceScope: String, Codable, Sendable {
    case global
    case focused
    case supportive
}
