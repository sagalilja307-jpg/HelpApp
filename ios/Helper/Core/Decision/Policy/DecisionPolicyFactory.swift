import Foundation

public struct DecisionPolicyFactory {

    public static func make(
        for mode: TemporaryContextMode
    ) -> DecisionPolicy {

        let allowLLM = mode != .supportive

        switch mode {

        case .normal:
            return DecisionPolicy(
                maxVisibleItems: 3,
                allowNudges: true,
                maxPromptsPerSession: 2,
                allowNewClusters: true,
                allowTaskBreakdown: false,
                tone: .neutral,
                requireGentleResponses: false,
                allowLLM: allowLLM
            )

        case .lowEnergy:
            return DecisionPolicy(
                maxVisibleItems: 2,
                allowNudges: false,
                maxPromptsPerSession: 0,
                allowNewClusters: false,
                allowTaskBreakdown: false,
                tone: .gentle,
                requireGentleResponses: true,
                allowLLM: allowLLM
            )

        case .overwhelmed:
            return DecisionPolicy(
                maxVisibleItems: 1,
                allowNudges: false,
                maxPromptsPerSession: 0,
                allowNewClusters: false,
                allowTaskBreakdown: false,
                tone: .gentle,
                requireGentleResponses: true,
                allowLLM: allowLLM
            )

        case .focused:
            return DecisionPolicy(
                maxVisibleItems: 5,
                allowNudges: true,
                maxPromptsPerSession: 3,
                allowNewClusters: true,
                allowTaskBreakdown: true,
                tone: .direct,
                requireGentleResponses: false,
                allowLLM: allowLLM
            )

        case .supportive:
            // Safety-first mode: observe, do not intervene
            return DecisionPolicy(
                maxVisibleItems: 1,
                allowNudges: false,
                maxPromptsPerSession: 0,
                allowNewClusters: false,
                allowTaskBreakdown: false,
                tone: .gentle,
                requireGentleResponses: true,
                allowLLM: false
            )
        }
    }
}
