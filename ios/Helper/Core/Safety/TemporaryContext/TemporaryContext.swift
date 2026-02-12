import Foundation
import SwiftData

/// Stores the currently active temporary context.
/// Only one context may exist at a time.
@Model
public final class TemporaryContext {

    @Attribute(.unique)
    public var id: String   // always "current"

    public var mode: TemporaryContextMode

    /// Optional system-readable reason (not user-facing)
    public var reason: String?

    public var updatedAt: Date

    public init(
        mode: TemporaryContextMode,
        reason: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = "current"
        self.mode = mode
        self.reason = reason
        self.updatedAt = updatedAt
    }
}
