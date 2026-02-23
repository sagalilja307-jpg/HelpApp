import Foundation
import SwiftData
#if canImport(PhotoKit)
@preconcurrency import PhotoKit
#endif
#if canImport(UIKit)
@preconcurrency import UIKit
#endif

protocol PhotosIndexing {

    @MainActor
    func indexIncremental(
        in context: ModelContext
    ) async throws -> Int

    @MainActor
    func fullScan(
        in context: ModelContext
    ) async throws -> Int

    func collectDelta(
        since: Date?,
        in context: ModelContext
    ) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry])
}

struct PhotosIndexService: PhotosIndexing {

    struct AssetSnapshot {
        let localIdentifier: String
        let title: String
        let bodySnippet: String
        let assetCreatedAt: Date?
        let assetUpdatedAt: Date?
        let isFavorite: Bool
        let ocrText: String?
        let ocrEnabled: Bool
        let ocrState: String
    }

    private let sourceConnectionStore: SourceConnectionStoring
    private let defaults: UserDefaults
    private let nowProvider: () -> Date

    init(
        sourceConnectionStore: SourceConnectionStoring = SourceConnectionStore.shared,
        defaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = DateService.shared.now
    ) {
        self.sourceConnectionStore = sourceConnectionStore
        self.defaults = defaults
        self.nowProvider = nowProvider
    }

    // MARK: - Public

    @MainActor
    func indexIncremental(
        in context: ModelContext
    ) async throws -> Int {

        let since = defaults.object(
            forKey: Self.incrementalCursorKey
        ) as? Date

        let count = try await indexAssets(
            modifiedAfter: since,
            fetchLimit: 500,
            in: context
        )

        defaults.set(
            nowProvider(),
            forKey: Self.incrementalCursorKey
        )

        return count
    }

    @MainActor
    func fullScan(
        in context: ModelContext
    ) async throws -> Int {

        let count = try await indexAssets(
            modifiedAfter: nil,
            fetchLimit: nil,
            in: context
        )

        defaults.set(
            nowProvider(),
            forKey: Self.incrementalCursorKey
        )

        return count
    }
    
    // MARK: - Convenience Methods
    
    @MainActor
    func indexAllPhotos(in context: ModelContext) async throws -> Int {
        return try await fullScan(in: context)
    }
    
    @MainActor
    func indexRecentPhotos(since date: Date, in context: ModelContext) async throws -> Int {
        return try await indexAssets(
            modifiedAfter: date,
            fetchLimit: 500,
            in: context
        )
    }
    
    func fetchIndexedPhoto(localIdentifier: String, in context: ModelContext) throws -> IndexedPhotoAsset? {
        let descriptor = FetchDescriptor<IndexedPhotoAsset>(
            predicate: #Predicate { $0.localIdentifier == localIdentifier }
        )
        return try context.fetch(descriptor).first
    }
    
    func searchPhotosByOCR(_ searchText: String, in context: ModelContext) throws -> [IndexedPhotoAsset] {
        let lowercased = searchText.lowercased()
        let descriptor = FetchDescriptor<IndexedPhotoAsset>(
            predicate: #Predicate { photo in
                photo.ocrText?.localizedStandardContains(lowercased) ?? false ||
                photo.title.localizedStandardContains(lowercased)
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func collectDelta(
        since: Date?,
        in context: ModelContext
    ) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {

        let descriptor = FetchDescriptor<IndexedPhotoAsset>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let rows = try context.fetch(descriptor)

        let filtered = rows.filter { row in
            guard let since else { return true }
            return row.updatedAt > since
        }

        return (
            filtered.map(Self.mapIndexedAsset),
            filtered.map(Self.makeEntry)
        )
    }
}
private extension PhotosIndexService {

    static let incrementalCursorKey =
        "helper.stage2.photos.last_indexed_at"

    func indexAssets(
        modifiedAfter since: Date?,
        fetchLimit: Int?,
        in context: ModelContext
    ) async throws -> Int {

        #if canImport(PhotoKit)

        let snapshots = try await fetchSnapshots(
            modifiedAfter: since,
            fetchLimit: fetchLimit
        )

        return try upsertSnapshots(
            snapshots,
            in: context
        )

        #else
        return 0
        #endif
    }

    func upsertSnapshots(
        _ snapshots: [AssetSnapshot],
        in context: ModelContext
    ) throws -> Int {

        guard !snapshots.isEmpty else { return 0 }

        let existing = try context.fetch(
            FetchDescriptor<IndexedPhotoAsset>()
        )

        var byIdentifier =
            Dictionary(uniqueKeysWithValues:
                existing.map { ($0.localIdentifier, $0) })

        let now = nowProvider()
        var changed = 0

        for snapshot in snapshots {

            let rowId = "photo:\(snapshot.localIdentifier)"

            if let row = byIdentifier[snapshot.localIdentifier] {

                let hasChanged =
                    row.title != snapshot.title ||
                    row.bodySnippet != snapshot.bodySnippet ||
                    row.assetCreatedAt != snapshot.assetCreatedAt ||
                    row.assetUpdatedAt != snapshot.assetUpdatedAt ||
                    row.isFavorite != snapshot.isFavorite ||
                    row.ocrText != snapshot.ocrText ||
                    row.ocrEnabled != snapshot.ocrEnabled ||
                    row.ocrState != snapshot.ocrState

                if !hasChanged { continue }

                row.id = rowId
                row.title = snapshot.title
                row.bodySnippet = snapshot.bodySnippet
                row.assetCreatedAt = snapshot.assetCreatedAt
                row.assetUpdatedAt = snapshot.assetUpdatedAt
                row.isFavorite = snapshot.isFavorite
                row.ocrText = snapshot.ocrText
                row.ocrEnabled = snapshot.ocrEnabled
                row.ocrState = snapshot.ocrState
                row.updatedAt = now

                changed += 1

            } else {

                let row = IndexedPhotoAsset(
                    id: rowId,
                    localIdentifier: snapshot.localIdentifier,
                    title: snapshot.title,
                    bodySnippet: snapshot.bodySnippet,
                    assetCreatedAt: snapshot.assetCreatedAt,
                    assetUpdatedAt: snapshot.assetUpdatedAt,
                    isFavorite: snapshot.isFavorite,
                    ocrText: snapshot.ocrText,
                    ocrEnabled: snapshot.ocrEnabled,
                    ocrState: snapshot.ocrState,
                    createdAt: now,
                    updatedAt: now
                )

                context.insert(row)
                byIdentifier[snapshot.localIdentifier] = row
                changed += 1
            }
        }

        if changed > 0 {
            try context.save()
        }

        return changed
    }
    
    nonisolated static func mapIndexedAsset(_ asset: IndexedPhotoAsset) -> UnifiedItemDTO {
        UnifiedItemDTO(
            id: asset.id,
            source: "photos",
            type: .photo,
            title: asset.title,
            body: asset.bodySnippet,
            createdAt: asset.createdAt,
            updatedAt: asset.updatedAt,
            startAt: asset.assetCreatedAt,
            endAt: nil,
            dueAt: nil,
            status: [
                "is_favorite": AnyCodable(asset.isFavorite),
                "ocr_enabled": AnyCodable(asset.ocrEnabled),
                "ocr_state": AnyCodable(asset.ocrState),
                "has_ocr_text": AnyCodable(asset.ocrText != nil)
            ]
        )
    }
    
    nonisolated static func makeEntry(_ asset: IndexedPhotoAsset) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(),
            source: .photos,
            title: asset.title,
            body: asset.bodySnippet,
            date: asset.assetCreatedAt ?? asset.createdAt
        )
    }
}
