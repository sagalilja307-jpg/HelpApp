import XCTest
@testable import Helper

@MainActor
final class ShareImportServiceTests: XCTestCase {

    func testSharedItemsEnvelopeCodableRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let envelope = SharedItemsEnvelope(
            version: .v1,
            items: [
                SharedItemPayload(
                    id: "item-1",
                    kind: .text,
                    value: "Packa pass",
                    source: "share_text",
                    createdAt: now
                ),
                SharedItemPayload(
                    id: "item-2",
                    kind: .url,
                    value: "https://example.com",
                    source: "share_url",
                    createdAt: now
                )
            ],
            createdAt: now
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(envelope)
        let decoded = try decoder.decode(SharedItemsEnvelope.self, from: data)

        XCTAssertEqual(decoded.version, .v1)
        XCTAssertEqual(decoded.items.count, 2)
        XCTAssertEqual(decoded.items.first?.kind, .text)
        XCTAssertEqual(decoded.items.last?.kind, .url)
    }
}
