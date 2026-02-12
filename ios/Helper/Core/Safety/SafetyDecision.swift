import Foundation

/// Final result of a safety decision.
/// This controls how the system reacts.
public struct SafetyDecision: Sendable {

    /// Overall system mode after evaluation
    public let mode: SystemMode

    /// Whether AI / assistant logic may proceed
    public let allowAIAction: Bool

    /// Optional safe replacement message
    public let messageOverride: String?

    /// Whether supportive TemporaryContext should be activated
    public let triggerSupportiveContext: Bool
}
