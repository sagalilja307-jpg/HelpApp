import Foundation

public struct DecisionPolicyFactory {

    public static func effectiveSupportLevel(
        baseLevel: Int,
        temporaryMode: TemporaryContextMode?
    ) -> Int {
        let clampedBase = max(0, min(3, baseLevel))
        guard let temporaryMode else { return clampedBase }

        switch temporaryMode {
        case .supportive:
            return 0
        case .lowEnergy, .overwhelmed:
            return min(clampedBase, 1)
        case .normal, .focused:
            return clampedBase
        }
    }

    public static func make(
        forSupportLevel supportLevel: Int,
        temporaryMode: TemporaryContextMode? = nil
    ) -> DecisionPolicy {
        let level = effectiveSupportLevel(baseLevel: supportLevel, temporaryMode: temporaryMode)

        switch level {
        case 0:
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
        case 1:
            return DecisionPolicy(
                maxVisibleItems: 2,
                allowNudges: true,
                maxPromptsPerSession: 1,
                allowNewClusters: false,
                allowTaskBreakdown: false,
                tone: .neutral,
                requireGentleResponses: true,
                allowLLM: false
            )
        case 2:
            return DecisionPolicy(
                maxVisibleItems: 3,
                allowNudges: true,
                maxPromptsPerSession: 3,
                allowNewClusters: true,
                allowTaskBreakdown: true,
                tone: .neutral,
                requireGentleResponses: true,
                allowLLM: true
            )
        default:
            return DecisionPolicy(
                maxVisibleItems: 5,
                allowNudges: true,
                maxPromptsPerSession: 5,
                allowNewClusters: true,
                allowTaskBreakdown: true,
                tone: .direct,
                requireGentleResponses: false,
                allowLLM: true
            )
        }
    }

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
