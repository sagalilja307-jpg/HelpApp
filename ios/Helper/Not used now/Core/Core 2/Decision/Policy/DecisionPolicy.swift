import Foundation

/// Bestämmer hur systemet ska agera i olika sammanhang (per session).
public struct DecisionPolicy: Codable, Sendable {
    public let maxVisibleItems: Int
    public let allowNudges: Bool
    public let maxPromptsPerSession: Int
    public let allowNewClusters: Bool
    public let allowTaskBreakdown: Bool
    public let tone: InteractionTone?
    public let requireGentleResponses: Bool
    public let allowLLM: Bool

    public init(
        maxVisibleItems: Int = 3,
        allowNudges: Bool = true,
        maxPromptsPerSession: Int = 5,
        allowNewClusters: Bool = true,
        allowTaskBreakdown: Bool = true,
        tone: InteractionTone? = nil,
        requireGentleResponses: Bool = false,
        allowLLM: Bool = true
    ) {
        self.maxVisibleItems = maxVisibleItems
        self.allowNudges = allowNudges
        self.maxPromptsPerSession = maxPromptsPerSession
        self.allowNewClusters = allowNewClusters
        self.allowTaskBreakdown = allowTaskBreakdown
        self.tone = tone
        self.requireGentleResponses = requireGentleResponses
        self.allowLLM = allowLLM
    }
}


/// Ger en smidig metod för att modifiera en policy utan att duplicera kod.
public extension DecisionPolicy {

    func with(
        maxVisibleItems: Int? = nil,
        allowNudges: Bool? = nil,
        maxPromptsPerSession: Int? = nil,
        allowNewClusters: Bool? = nil,
        allowTaskBreakdown: Bool? = nil,
        allowLLM: Bool? = nil,
        tone: InteractionTone? = nil,
        requireGentleResponses: Bool? = nil
    ) -> DecisionPolicy {

        return DecisionPolicy(
            maxVisibleItems: maxVisibleItems ?? self.maxVisibleItems,
            allowNudges: allowNudges ?? self.allowNudges,
            maxPromptsPerSession: maxPromptsPerSession ?? self.maxPromptsPerSession,
            allowNewClusters: allowNewClusters ?? self.allowNewClusters,
            allowTaskBreakdown: allowTaskBreakdown ?? self.allowTaskBreakdown,
            tone: tone ?? self.tone,
            requireGentleResponses: requireGentleResponses ?? self.requireGentleResponses,
            allowLLM: allowLLM ?? self.allowLLM
        )
    }
}
