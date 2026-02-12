import Foundation

/// Defines all allowed preference keys.
public enum PreferenceKey: String, Codable, Sendable {

    // Interaction
    case toneInGeneral
    case toneWhenFocused
    case toneWhenSupportive

    // Content & structure
    case preferShortMessages
    case dislikeChecklists

    // Crisis / sensitive moments
    case crisisNotes
}
