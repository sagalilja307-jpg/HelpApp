import Foundation

/// Result of evaluating user input for safety.
/// This does NOT describe the user, only system permission.
public enum SafetyPolicy: Sendable {
    case allow
    case restrict(reason: SafetyRestriction)
}
