import Foundation

public final class SafetyDecisionEngine {

    // Compose pipeline with all active policies
    private static let pipeline = SafetyPipeline(policies: [
        SelfHarmRiskPolicy()
        // Lägg till fler policies här vid behov
    ])

    public static func decide(userInput: String) -> SafetyDecision {
        switch pipeline.evaluate(input: userInput) {
        case .allow:
            return SafetyDecision(
                mode: .normal,
                allowAIAction: true,
                messageOverride: nil,
                triggerSupportiveContext: false
            )

        case .restrict(let reason):
            switch reason {
            case .selfHarmRisk:
                return SafetyDecision(
                    mode: .supportive,
                    allowAIAction: false,
                    messageOverride: """
                    Jag kan inte hjälpa till med sådant som kan skada dig.
                    Men jag bryr mig om att du är trygg.

                    Om du vill kan vi ta det lugnt, eller fokusera på något som känns lite lättare just nu.
                    """,
                    triggerSupportiveContext: true
                )
            }
        }
    }
}
