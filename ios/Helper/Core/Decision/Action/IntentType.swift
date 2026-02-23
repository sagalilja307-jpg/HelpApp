import Foundation

/// Describes the user's likely intent based on provided content.
/// This is a suggestion — never a decision.
public enum IntentType {
    case calendar
    case reminder
    case note
    case sendMessage
    case followUp
    case none
}

