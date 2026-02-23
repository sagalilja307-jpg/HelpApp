import Foundation

/// Describes why the system restricts certain actions.
/// This is a system boundary, not an interpretation of the user.
public enum SafetyRestriction: String, Sendable {
    case selfHarmRisk
}
