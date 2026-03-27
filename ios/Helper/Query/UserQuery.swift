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
    let clarificationContext: BackendQueryClarificationContextDTO?

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = DateService.shared.now(),
        source: Source = .userTyped,
        clarificationContext: BackendQueryClarificationContextDTO? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.source = source
        self.clarificationContext = clarificationContext
    }
}
