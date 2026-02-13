import XCTest
import SwiftData
@testable import Helper

@MainActor
final class ContactsCollectorServiceTests: XCTestCase {

    func testSnapshotHashIsStableAndMapsToContactItem() {
        let snapshotA = ContactsCollectorService.makeSnapshot(
            identifier: "abc",
            fullName: "Alva Andersson",
            organization: "Resegruppen",
            emails: ["alva@example.com"],
            phones: ["+46701234567"]
        )
        let snapshotB = ContactsCollectorService.makeSnapshot(
            identifier: "abc",
            fullName: "Alva Andersson",
            organization: "Resegruppen",
            emails: ["alva@example.com"],
            phones: ["+46701234567"]
        )

        XCTAssertEqual(snapshotA.hash, snapshotB.hash)

        let row = IndexedContact(
            id: "contact:abc",
            contactIdentifier: snapshotA.identifier,
            fullName: snapshotA.fullName,
            organization: snapshotA.organization,
            bodySnippet: "Resegruppen\nE-post: alva@example.com\nTelefon: +46701234567",
            hasEmail: true,
            hasPhone: true,
            contactHash: snapshotA.hash,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let mapped = ContactsCollectorService.mapIndexedContact(row)
        XCTAssertEqual(mapped.id, "contact:abc")
        XCTAssertEqual(mapped.source, "contacts")
        XCTAssertEqual(mapped.type, .contact)
        XCTAssertEqual(mapped.title, "Alva Andersson")
        XCTAssertEqual(mapped.status["has_email"], AnyCodable(true))
        XCTAssertEqual(mapped.status["has_phone"], AnyCodable(true))
    }

    func testCollectDeltaRespectsCheckpoint() throws {
        let container = try ModelContainer(
            for: IndexedContact.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        context.insert(
            IndexedContact(
                id: "contact:old",
                contactIdentifier: "old",
                fullName: "Old Contact",
                organization: "",
                bodySnippet: "",
                hasEmail: false,
                hasPhone: false,
                contactHash: "old",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        )
        context.insert(
            IndexedContact(
                id: "contact:new",
                contactIdentifier: "new",
                fullName: "New Contact",
                organization: "Travel",
                bodySnippet: "Travel\nE-post: new@example.com",
                hasEmail: true,
                hasPhone: false,
                contactHash: "new",
                createdAt: Date(timeIntervalSince1970: 30),
                updatedAt: Date(timeIntervalSince1970: 40)
            )
        )
        try context.save()

        let service = ContactsCollectorService(context: context)
        let delta = try service.collectDelta(since: Date(timeIntervalSince1970: 25))

        XCTAssertEqual(delta.items.count, 1)
        XCTAssertEqual(delta.items.first?.id, "contact:new")
        XCTAssertEqual(delta.entries.first?.source, .contacts)
    }
}
