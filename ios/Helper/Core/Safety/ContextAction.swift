import Foundation

/// Discrete user-triggered actions (buttons).
/// These do not describe feelings, only intent.
public enum ContextAction: String, Codable, Sendable {
    case setNormal
    case setLowEnergy
    case setOverwhelmed
    case setFocused
    case setSupportive

    /// Safety-specific
    case acknowledgeSafetyAndContinue   // "Jag är okej nu"
}
