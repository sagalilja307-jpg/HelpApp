import Foundation
import SwiftData

@Model
public final class UserNote {
    @Attribute(.unique)
    public var id: String

    public var title: String
    public var body: String
    public var source: String
    public var externalRef: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        source: String,
        externalRef: String? = nil,
        createdAt: Date = DateService.shared.now(),
        updatedAt: Date = DateService.shared.now()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.source = source
        self.externalRef = externalRef
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
