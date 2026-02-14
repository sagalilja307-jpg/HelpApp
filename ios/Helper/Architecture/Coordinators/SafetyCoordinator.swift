import Foundation
import SwiftData

@MainActor
public final class SafetyCoordinator {
    
    private let memoryService: MemoryService
    
    public init(memoryService: MemoryService) {
        self.memoryService = memoryService
    }

    public func handle(userInput: String) throws -> SafetyDecision {
        let context = memoryService.context()

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

