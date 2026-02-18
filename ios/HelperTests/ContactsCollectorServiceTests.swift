import XCTest
import SwiftData
@testable import Helper

@MainActor
final class ContactsCollectorServiceTests: XCTestCase {

    func testCollectDeltaMapsIndexedContactToUnifiedItem() throws {
        let container = try ModelContainer(
            for: IndexedContact.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        context.insert(
            IndexedContact(
                id: "contact:abc",
                contactIdentifier: "abc",
                fullName: "Alva Andersson",
                organization: "Resegruppen",
                bodySnippet: "Org: Resegruppen | E-post: alva@example.com | Tel: +46701234567",
                hasEmail: true,
                hasPhone: true,
                contactHash: "hash-1",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )
        try context.save()

        let service = ContactsCollectorService()
        let delta = try service.collectDelta(since: nil, in: context)

        XCTAssertEqual(delta.items.count, 1)
        XCTAssertEqual(delta.items.first?.id, "contact:abc")
        XCTAssertEqual(delta.items.first?.source, "contacts")
        XCTAssertEqual(delta.items.first?.type, .contact)
        XCTAssertEqual(delta.items.first?.title, "Alva Andersson")
        XCTAssertEqual(delta.items.first?.status["has_email"], AnyCodable(true))
        XCTAssertEqual(delta.items.first?.status["has_phone"], AnyCodable(true))
        XCTAssertEqual(delta.entries.first?.source, .contacts)
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
                bodySnippet: "Org: Travel | E-post: new@example.com",
                hasEmail: true,
                hasPhone: false,
                contactHash: "new",
                createdAt: Date(timeIntervalSince1970: 30),
                updatedAt: Date(timeIntervalSince1970: 40)
            )
        )
        try context.save()

        let service = ContactsCollectorService()
        let delta = try service.collectDelta(since: Date(timeIntervalSince1970: 25), in: context)

        XCTAssertEqual(delta.items.count, 1)
        XCTAssertEqual(delta.items.first?.id, "contact:new")
        XCTAssertEqual(delta.entries.first?.source, .contacts)
    }
}
