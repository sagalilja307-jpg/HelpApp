import Foundation

// MARK: - Actor

/// Identifierar en aktör i systemet (användare, AI, system, utvecklare).
public enum Actor: String, Sendable {
    case system
    case ai
    case user
    case developer
}

// MARK: - StorePermission

/// Anger vilka aktörer som får skriva till en viss datalagring,
/// och om det är ett append-only-lager.
public struct StorePermission: Sendable {
    public let canWrite: Set<Actor>
    public let appendOnly: Bool

    public init(
        canWrite: Set<Actor>,
        appendOnly: Bool = false
    ) {
        self.canWrite = canWrite
        self.appendOnly = appendOnly
    }
}

// MARK: - MemoryError

/// Specifika fel kopplade till minnesåtkomst och rättigheter.
public enum MemoryError: Error, LocalizedError {
    case permissionDenied(actor: Actor, store: String)
    case appendOnlyViolation(store: String)
    case invalidValue(_ message: String)

    public var errorDescription: String? {
        switch self {
        case let .permissionDenied(actor, store):
            return "\(actor.rawValue) cannot write to \(store)"
        case let .appendOnlyViolation(store):
            return "\(store) is append-only; update/delete is not allowed via this API"
        case let .invalidValue(message):
            return message
        }
    }
}

