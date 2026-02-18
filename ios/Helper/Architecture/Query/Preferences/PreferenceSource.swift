import Foundation

/// Describes how a preference was created.
public enum PreferenceSource: String, Codable, Sendable {
    case userExplicit
    case systemSuggested
}
