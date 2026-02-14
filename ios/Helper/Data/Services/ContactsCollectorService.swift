import Foundation
import SwiftData
import CryptoKit
#if canImport(Contacts)
import Contacts
#endif

protocol ContactsCollecting {
    func refreshIndex() throws -> Int
    func collectDelta(since: Date?) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry])
}

struct ContactsCollectorService: ContactsCollecting {
    struct ContactSnapshot {
        let identifier: String
        let fullName: String
        let organization: String
        let emails: [String]
        let phones: [String]
        let hash: String
    }

    private let memoryService: MemoryService?
    private let modelContext: ModelContext?

    #if canImport(Contacts)
    private let contactStore: CNContactStore
    #endif

    init(memoryService: MemoryService) {
        self.memoryService = memoryService
        self.modelContext = nil
        #if canImport(Contacts)
        self.contactStore = CNContactStore()
        #endif
    }

    #if canImport(Contacts)
    init(context: ModelContext, contactStore: CNContactStore = CNContactStore()) {
        self.memoryService = nil
        self.modelContext = context
        self.contactStore = contactStore
    }
    #else
    init(context: ModelContext) {
        self.memoryService = nil
        self.modelContext = context
    }
    #endif

    func refreshIndex() throws -> Int {
        #if canImport(Contacts)
        let snapshots = try fetchSnapshots()
        let context = context()

        let existing = try context.fetch(FetchDescriptor<IndexedContact>())
        var existingByIdentifier: [String: IndexedContact] = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.contactIdentifier, $0) }
        )

        var changedCount = 0
        let now = Date()

        for snapshot in snapshots {
            if let row = existingByIdentifier[snapshot.identifier] {
                if row.contactHash == snapshot.hash {
                    continue
                }
                row.fullName = snapshot.fullName
                row.organization = snapshot.organization
                row.bodySnippet = Self.contactBody(
                    organization: snapshot.organization,
                    emails: snapshot.emails,
                    phones: snapshot.phones
                )
                row.hasEmail = !snapshot.emails.isEmpty
                row.hasPhone = !snapshot.phones.isEmpty
                row.contactHash = snapshot.hash
                row.updatedAt = now
                changedCount += 1
            } else {
                let body = Self.contactBody(
                    organization: snapshot.organization,
                    emails: snapshot.emails,
                    phones: snapshot.phones
                )
                let row = IndexedContact(
                    id: "contact:\(snapshot.identifier)",
                    contactIdentifier: snapshot.identifier,
                    fullName: snapshot.fullName,
                    organization: snapshot.organization,
                    bodySnippet: body,
                    hasEmail: !snapshot.emails.isEmpty,
                    hasPhone: !snapshot.phones.isEmpty,
                    contactHash: snapshot.hash,
                    createdAt: now,
                    updatedAt: now
                )
                context.insert(row)
                existingByIdentifier[snapshot.identifier] = row
                changedCount += 1
            }
        }

        if changedCount > 0 {
            try context.save()
        }

        return changedCount
        #else
        return 0
        #endif
    }

    func collectDelta(since: Date?) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        let context = context()
        let descriptor = FetchDescriptor<IndexedContact>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let rows = try context.fetch(descriptor)
        let filtered = rows.filter { row in
            guard let since else { return true }
            return row.updatedAt > since
        }

        let items = filtered.map(Self.mapIndexedContact)
        let entries = filtered.map(Self.makeEntry)
        return (items, entries)
    }
}

extension ContactsCollectorService {
    static func makeSnapshot(
        identifier: String,
        fullName: String,
        organization: String,
        emails: [String],
        phones: [String]
    ) -> ContactSnapshot {
        let signature = [
            identifier,
            fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            organization.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            emails.map { $0.lowercased() }.sorted().joined(separator: ","),
            phones.sorted().joined(separator: ",")
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(signature.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()

        return ContactSnapshot(
            identifier: identifier,
            fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Kontakt"
                : fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            organization: organization.trimmingCharacters(in: .whitespacesAndNewlines),
            emails: emails,
            phones: phones,
            hash: hash
        )
    }

    nonisolated static func mapIndexedContact(_ row: IndexedContact) -> UnifiedItemDTO {
        UnifiedItemDTO(
            id: row.id,
            source: "contacts",
            type: .contact,
            title: row.fullName,
            body: row.bodySnippet,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            startAt: nil,
            endAt: nil,
            dueAt: nil,
            status: [
                "has_email": AnyCodable(row.hasEmail),
                "has_phone": AnyCodable(row.hasPhone),
                "contact_hash": AnyCodable(row.contactHash)
            ]
        )
    }

    nonisolated static func makeEntry(_ row: IndexedContact) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(),
            source: .contacts,
            title: row.fullName,
            body: row.bodySnippet.isEmpty ? nil : row.bodySnippet,
            date: row.updatedAt
        )
    }
}

private extension ContactsCollectorService {
    func context() -> ModelContext {
        if let modelContext {
            return modelContext
        }
        if let memoryService {
            return memoryService.context()
        }
        fatalError("ContactsCollectorService saknar ModelContext och MemoryService.")
    }

    static func contactBody(organization: String, emails: [String], phones: [String]) -> String {
        var parts: [String] = []

        let org = organization.trimmingCharacters(in: .whitespacesAndNewlines)
        if !org.isEmpty {
            parts.append(org)
        }
        if !emails.isEmpty {
            parts.append("E-post: \(emails.joined(separator: ", "))")
        }
        if !phones.isEmpty {
            parts.append("Telefon: \(phones.joined(separator: ", "))")
        }

        return parts.joined(separator: "\n")
    }

    #if canImport(Contacts)
    func fetchSnapshots() throws -> [ContactSnapshot] {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        var snapshots: [ContactSnapshot] = []

        try contactStore.enumerateContacts(with: request) { contact, _ in
            let fullName = CNContactFormatter.string(from: contact, style: .fullName)
                ?? [contact.givenName, contact.middleName, contact.familyName]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")

            let emails = contact.emailAddresses
                .map { $0.value as String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let phones = contact.phoneNumbers
                .map { $0.value.stringValue }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            snapshots.append(
                Self.makeSnapshot(
                    identifier: contact.identifier,
                    fullName: fullName,
                    organization: contact.organizationName,
                    emails: emails,
                    phones: phones
                )
            )
        }

        return snapshots
    }
    #endif
}
