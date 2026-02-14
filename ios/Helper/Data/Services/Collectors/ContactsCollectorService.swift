import Foundation
import SwiftData
import CryptoKit
#if canImport(Contacts)
import Contacts
#endif

protocol ContactsCollecting {
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
    #endif

    init(
        #if canImport(Contacts)
        contactStore: CNContactStore = CNContactStore()
        #endif
    ) {
        #if canImport(Contacts)
        self.contactStore = contactStore
        #endif
    }

    // MARK: - Refresh

    func refreshIndex(
        in context: ModelContext
    ) throws -> Int {

        #if canImport(Contacts)

        let snapshots = try fetchSnapshots()

        let existing = try context.fetch(FetchDescriptor<IndexedContact>())
        var existingByIdentifier =
            Dictionary(uniqueKeysWithValues: existing.map { ($0.contactIdentifier, $0) })

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

    // MARK: - Collect

    func collectDelta(
        since: Date?,
        in context: ModelContext
    ) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {

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
