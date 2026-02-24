import Foundation
import SwiftData
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
    let contactStore: CNContactStore
    
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
}
