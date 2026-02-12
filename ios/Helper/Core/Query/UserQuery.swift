import Foundation

/// A user question/query with minimal metadata.
struct UserQuery: Identifiable, Equatable, Sendable, Codable {
    enum Source: String, Codable, Sendable {
        case userTyped
        case voice
        case shortcut
        case unknown
    }

    let id: UUID
    let text: String
    let createdAt: Date
    let source: Source

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        source: Source = .userTyped
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.source = source
    }
}
