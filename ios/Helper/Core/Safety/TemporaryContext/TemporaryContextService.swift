import Foundation
import SwiftData

public final class TemporaryContextService {

    // MARK: - Read

    public static func getCurrent(
        in context: ModelContext
    ) throws -> TemporaryContext? {

        var descriptor = FetchDescriptor<TemporaryContext>(
            predicate: #Predicate { $0.id == "current" }
        )
        descriptor.fetchLimit = 1

        return try context.fetch(descriptor).first
    }

    // MARK: - Set

    public static func set(
        actor: Actor,
        mode: TemporaryContextMode,
        reason: String?,
        in context: ModelContext
    ) throws {

        switch actor {
        case .user:
            break // always allowed

        case .system:
            guard mode == .supportive else {
                throw MemoryError.permissionDenied(
                    actor: actor,
                    store: "temporary_context(system_only_supportive)"
                )
            }

        default:
            throw MemoryError.permissionDenied(
                actor: actor,
                store: "temporary_context"
            )
        }

        var descriptor = FetchDescriptor<TemporaryContext>(
            predicate: #Predicate { $0.id == "current" }
        )
        descriptor.fetchLimit = 1

        let existing = try context.fetch(descriptor).first

        if let existing {
            existing.mode = mode
            existing.reason = reason
            existing.updatedAt = Date()
        } else {
            context.insert(
                TemporaryContext(
                    mode: mode,
                    reason: reason
                )
            )
        }

        try context.save()
    }

    // MARK: - Clear (user-only)

    public static func clear(
        actor: Actor,
        in context: ModelContext
    ) throws {

        guard actor == .user else {
            throw MemoryError.permissionDenied(
                actor: actor,
                store: "temporary_context.clear(user_only)"
            )
        }

        let all = try context.fetch(FetchDescriptor<TemporaryContext>())
        for item in all {
            context.delete(item)
        }

        try context.save()
    }

    // MARK: - Handle ContextAction

    public static func handleAction(
        actor: Actor,
        action: ContextAction,
        memoryService: MemoryService,
        context: ModelContext
    ) throws {

        guard let mode = ContextActionMapper.mode(for: action) else {
            return
        }

        // User explicitly acknowledges safety and wants to continue
        if action == .acknowledgeSafetyAndContinue {

            try set(
                actor: .user,
                mode: .normal,
                reason: "user_acknowledged_safety",
                in: context
            )

            try memoryService.appendDecision(
                actor: .system,
                decisionId: UUID().uuidString,
                action: .safetyAcknowledged,
                reason: ["user_indicated_ok"],
                usedMemory: nil,
                in: context
            )

            return
        }

        // Regular context change
        try set(
            actor: actor,
            mode: mode,
            reason: "manual_context_action",
            in: context
        )

        try memoryService.appendDecision(
            actor: .system,
            decisionId: UUID().uuidString,
            action: .contextChanged,
            reason: [action.rawValue],
            usedMemory: nil,
            in: context
        )
    }
}
