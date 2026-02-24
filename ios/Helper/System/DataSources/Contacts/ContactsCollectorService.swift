import Foundation
import SwiftData
import CryptoKit
#if canImport(Contacts)
@preconcurrency import Contacts
#endif

protocol ContactsCollecting {
    @MainActor
    func refreshIndex(
        in context: ModelContext
    ) throws -> Int

    func collectDelta(
        since: Date?,
        in context: ModelContext
    ) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry])
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

    #if canImport(Contacts)
    private let contactStore: CNContactStore
    
    init(contactStore: CNContactStore = CNContactStore()) {
        self.contactStore = contactStore
    }
    #else
    init() {}
    #endif

    // MARK: - Refresh

    // MARK: - Convenience Methods
    
    @MainActor
    func indexAllContacts(in context: ModelContext) async throws -> Int {
        return try refreshIndex(in: context)
    }
    
    func fetchIndexedContact(identifier: String, in context: ModelContext) throws -> IndexedContact? {
        let descriptor = FetchDescriptor<IndexedContact>(
            predicate: #Predicate { $0.contactIdentifier == identifier }
        )
        return try context.fetch(descriptor).first
    }
    
    func searchContactsByName(_ searchText: String, in context: ModelContext) throws -> [IndexedContact] {
        let lowercased = searchText.lowercased()
        let descriptor = FetchDescriptor<IndexedContact>(
            predicate: #Predicate { contact in
                contact.fullName.localizedStandardContains(lowercased) ||
                contact.organization.localizedStandardContains(lowercased) ||
                contact.bodySnippet.localizedStandardContains(lowercased)
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    @MainActor
    func refreshIndex(
        in context: ModelContext
    ) throws -> Int {
        let op = "ContactsRefreshIndex"
        DataSourceDebug.start(op)
        do {
            #if canImport(Contacts)

            let snapshots = try fetchSnapshots()

            let existing = try context.fetch(FetchDescriptor<IndexedContact>())
            var existingByIdentifier =
                Dictionary(uniqueKeysWithValues: existing.map { ($0.contactIdentifier, $0) })

            var changedCount = 0
            let now = DateService.shared.now()

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

            DataSourceDebug.success(op, count: changedCount)
            return changedCount

            #else
            DataSourceDebug.success(op, count: 0)
            return 0
            #endif
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }

    // MARK: - Collect

    func collectDelta(
        since: Date?,
        in context: ModelContext
    ) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        let op = "ContactsCollect"
        DataSourceDebug.start(op)
        do {
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

            DataSourceDebug.success(op, count: filtered.count)
            return (items, entries)
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }
    
    // MARK: - Private Helpers
    
    #if canImport(Contacts)
    private func fetchSnapshots() throws -> [ContactSnapshot] {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        
        let request = CNContactFetchRequest(keysToFetch: keys)
        var snapshots: [ContactSnapshot] = []
        
        try contactStore.enumerateContacts(with: request) { contact, _ in
            let fullName = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            guard !fullName.isEmpty else { return }
            
            let organization = contact.organizationName
            let emails = contact.emailAddresses.map { $0.value as String }
            let phones = contact.phoneNumbers.map { $0.value.stringValue }
            
            let hash = Self.computeHash(
                name: fullName,
                org: organization,
                emails: emails,
                phones: phones
            )
            
            snapshots.append(ContactSnapshot(
                identifier: contact.identifier,
                fullName: fullName,
                organization: organization,
                emails: emails,
                phones: phones,
                hash: hash
            ))
        }
        
        return snapshots
    }
    
    private static func computeHash(
        name: String,
        org: String,
        emails: [String],
        phones: [String]
    ) -> String {
        let combined = "\(name)|\(org)|\(emails.joined(separator: ","))|\(phones.joined(separator: ","))"
        return String(combined.hashValue)
    }
    #endif
    
    private static func contactBody(
        organization: String,
        emails: [String],
        phones: [String]
    ) -> String {
        var parts: [String] = []
        
        if !organization.isEmpty {
            parts.append("Org: \(organization)")
        }
        
        if !emails.isEmpty {
            parts.append("E-post: \(emails.joined(separator: ", "))")
        }
        
        if !phones.isEmpty {
            parts.append("Tel: \(phones.joined(separator: ", "))")
        }
        
        return parts.isEmpty ? "Kontakt" : parts.joined(separator: " | ")
    }
    
    nonisolated private static func mapIndexedContact(_ contact: IndexedContact) -> UnifiedItemDTO {
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
    
    nonisolated private static func makeEntry(_ contact: IndexedContact) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(),
            source: .contacts,
            title: contact.fullName,
            body: contact.bodySnippet,
            date: contact.updatedAt
        )
    }
}
