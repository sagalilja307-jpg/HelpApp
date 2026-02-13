import XCTest
import SwiftData
@testable import Helper

@MainActor
final class PhotosIndexServiceTests: XCTestCase {

    func testSnapshotRespectsOCROffAndOn() {
        let createdAt = Date(timeIntervalSince1970: 1_700_100_000)

        let ocrOff = PhotosIndexService.makeSnapshot(
            localIdentifier: "asset-off",
            assetCreatedAt: createdAt,
            assetUpdatedAt: createdAt,
            isFavorite: false,
            metadataSnippet: "Skapad: 2026-02-13",
            ocrText: nil,
            ocrEnabled: false
        )
        XCTAssertEqual(ocrOff.ocrState, "disabled")
        XCTAssertEqual(ocrOff.bodySnippet, "Skapad: 2026-02-13")

        let ocrOn = PhotosIndexService.makeSnapshot(
            localIdentifier: "asset-on",
            assetCreatedAt: createdAt,
            assetUpdatedAt: createdAt,
            isFavorite: true,
            metadataSnippet: "Skapad: 2026-02-13",
            ocrText: "Boarding 08:00",
            ocrEnabled: true
        )
        XCTAssertEqual(ocrOn.ocrState, "completed")
        XCTAssertEqual(ocrOn.bodySnippet, "Boarding 08:00")
    }

    func testCollectDeltaUsesUpdatedAtCheckpoint() throws {
        let container = try ModelContainer(
            for: IndexedPhotoAsset.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        context.insert(
            IndexedPhotoAsset(
                id: "photo:old",
                localIdentifier: "old",
                title: "Old Photo",
                bodySnippet: "old",
                assetCreatedAt: Date(timeIntervalSince1970: 10),
                assetUpdatedAt: Date(timeIntervalSince1970: 10),
                isFavorite: false,
                ocrText: nil,
                ocrEnabled: false,
                ocrState: "disabled",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        )
        context.insert(
            IndexedPhotoAsset(
                id: "photo:new",
                localIdentifier: "new",
                title: "New Photo",
                bodySnippet: "new",
                assetCreatedAt: Date(timeIntervalSince1970: 30),
                assetUpdatedAt: Date(timeIntervalSince1970: 30),
                isFavorite: true,
                ocrText: "gate 42",
                ocrEnabled: true,
                ocrState: "completed",
                createdAt: Date(timeIntervalSince1970: 30),
                updatedAt: Date(timeIntervalSince1970: 40)
            )
        )
        try context.save()

        let service = PhotosIndexService(context: context)
        let delta = try service.collectDelta(since: Date(timeIntervalSince1970: 25))

        XCTAssertEqual(delta.items.count, 1)
        XCTAssertEqual(delta.items.first?.id, "photo:new")
        XCTAssertEqual(delta.items.first?.type, .photo)
        XCTAssertEqual(delta.entries.first?.source, .photos)
    }
}
