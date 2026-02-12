import Foundation

/// Represents any user-provided content entering the app.
/// This is the single source of truth for all input.
struct ContentObject: Identifiable, Equatable, Sendable {

    // MARK: - Identity
    let id: UUID

    // MARK: - Raw content
    let rawText: String

    // MARK: - Metadata
    let source: ContentSource
    let createdAt: Date

    // MARK: - Optional context
    let originalDateHint: Date?
    let relatedEntityId: String?

    // MARK: - Init
    init(
        rawText: String,
        source: ContentSource,
        createdAt: Date = Date(),
        originalDateHint: Date? = nil,
        relatedEntityId: String? = nil
    ) {
        self.id = UUID()
        self.rawText = rawText
        self.source = source
        self.createdAt = createdAt
        self.originalDateHint = originalDateHint
        self.relatedEntityId = relatedEntityId
    }
}
