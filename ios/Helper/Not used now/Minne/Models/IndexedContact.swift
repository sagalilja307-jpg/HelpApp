import Foundation
import SwiftData

@Model
public final class IndexedContact {
    @Attribute(.unique)
    public var id: String

    public var contactIdentifier: String
    public var fullName: String
    public var organization: String
    public var bodySnippet: String
    public var hasEmail: Bool
    public var hasPhone: Bool
    public var contactHash: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        contactIdentifier: String,
        fullName: String,
        organization: String,
        bodySnippet: String,
        hasEmail: Bool,
        hasPhone: Bool,
        contactHash: String,
        createdAt: Date = DateService.shared.now(),
        updatedAt: Date = DateService.shared.now()
    ) {
        self.id = id
        self.contactIdentifier = contactIdentifier
        self.fullName = fullName
        self.organization = organization
        self.bodySnippet = bodySnippet
        self.hasEmail = hasEmail
        self.hasPhone = hasPhone
        self.contactHash = contactHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
