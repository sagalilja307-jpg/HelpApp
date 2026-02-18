import XCTest
import SwiftData
@testable import Helper

@MainActor
final class PhotosIndexServiceTests: XCTestCase {

    func testCollectDeltaPreservesOCRStateAndBody() throws {
        let container = try ModelContainer(
            for: IndexedPhotoAsset.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        context.insert(
            IndexedPhotoAsset(
                id: "photo:ocr-off",
                localIdentifier: "ocr-off",
                title: "OCR Off",
                bodySnippet: "Skapad: 2026-02-13",
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
                id: "photo:ocr-on",
                localIdentifier: "ocr-on",
                title: "OCR On",
                bodySnippet: "Boarding 08:00",
                assetCreatedAt: Date(timeIntervalSince1970: 30),
                assetUpdatedAt: Date(timeIntervalSince1970: 30),
                isFavorite: true,
                ocrText: "Boarding 08:00",
                ocrEnabled: true,
                ocrState: "completed",
                createdAt: Date(timeIntervalSince1970: 30),
                updatedAt: Date(timeIntervalSince1970: 40)
            )
        )
        try context.save()

        let service = PhotosIndexService()
        let delta = try service.collectDelta(since: nil, in: context)

        XCTAssertEqual(delta.items.count, 2)
        let byID = Dictionary(uniqueKeysWithValues: delta.items.map { ($0.id, $0) })
        XCTAssertEqual(byID["photo:ocr-off"]?.status["ocr_state"], AnyCodable("disabled"))
        XCTAssertEqual(byID["photo:ocr-on"]?.status["ocr_state"], AnyCodable("completed"))
        XCTAssertEqual(byID["photo:ocr-off"]?.body, "Skapad: 2026-02-13")
        XCTAssertEqual(byID["photo:ocr-on"]?.body, "Boarding 08:00")
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

        let service = PhotosIndexService()
        let delta = try service.collectDelta(since: Date(timeIntervalSince1970: 25), in: context)

        XCTAssertEqual(delta.items.count, 1)
        XCTAssertEqual(delta.items.first?.id, "photo:new")
        XCTAssertEqual(delta.items.first?.type, .photo)
        XCTAssertEqual(delta.entries.first?.source, .photos)
    }
}
