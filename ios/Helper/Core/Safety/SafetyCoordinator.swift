import Foundation
import SwiftData

public final class SafetyCoordinator {

    public static func handle(
        userInput: String,
        memoryService: MemoryService,
        context: ModelContext
    ) throws -> SafetyDecision {

        let decision = SafetyDecisionEngine.decide(userInput: userInput)

        if decision.triggerSupportiveContext {

            try TemporaryContextService.set(
                actor: .system,
                mode: .supportive,
                reason: "safety_boundary_triggered",
                in: context
            )

            try memoryService.appendDecision(
                actor: .system,
                decisionId: UUID().uuidString,
                action: .safetyBoundaryTriggered,
                reason: ["self_harm_risk"],
                usedMemory: nil,
                in: context
            )
        }

        return decision
    }
}

