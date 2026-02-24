import Foundation

extension ContactsCollectorService {

    // MARK: - Mapping

    nonisolated static func mapIndexedContact(_ contact: IndexedContact) -> UnifiedItemDTO {
        UnifiedItemDTO(
            id: contact.id,
            source: "contacts",
            type: .contact,
            title: contact.fullName,
            body: contact.bodySnippet,
            createdAt: contact.createdAt,
            updatedAt: contact.updatedAt,
            startAt: nil,
            endAt: nil,
            dueAt: nil,
            status: [
                "organization": AnyCodable(contact.organization),
                "has_email": AnyCodable(contact.hasEmail),
                "has_phone": AnyCodable(contact.hasPhone)
            ]
        )
    }

    nonisolated static func makeEntry(_ contact: IndexedContact) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(),
            source: .contacts,
            title: contact.fullName,
            body: contact.bodySnippet,
            date: contact.updatedAt
        )
    }
}
