import Foundation

/// Samordnar och kör beslutsregler mot förslag.
final class DecisionEngine {

    private let pipeline = DecisionPipeline(policies: [
        SupportiveModePolicy(),
        AllowNudgesPolicy(),
        SuggestionTypePolicy()
        // Lägg till fler policies här
    ])

    func evaluate(
        suggestion: ActionSuggestion,
        policy: DecisionPolicy,
        context: TemporaryContext?,
        clusterContext: ClusterContext? = nil
    ) -> DecisionAction {
        let ctx = DecisionContext(
            policy: policy,
            temporaryContext: context,
            clusterContext: clusterContext
        )
        return pipeline.evaluate(suggestion: suggestion, context: ctx)
    }
}

