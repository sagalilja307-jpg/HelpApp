import Foundation
import SwiftData

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

    let sourceConnectionStore: SourceConnectionStoring
    let defaults: UserDefaults
    let nowProvider: () -> Date

    init(
        sourceConnectionStore: SourceConnectionStoring = SourceConnectionStore.shared,
        defaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = DateService.shared.now
    ) {
        self.sourceConnectionStore = sourceConnectionStore
        self.defaults = defaults
        self.nowProvider = nowProvider
    }

    // MARK: - Public API

    @MainActor
    func indexIncremental(
        in context: ModelContext
    ) async throws -> Int {
        let op = "PhotosIndexIncremental"
        DataSourceDebug.start(op)
        do {
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

            DataSourceDebug.success(op, count: count)
            return count
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }

    @MainActor
    func fullScan(
        in context: ModelContext
    ) async throws -> Int {
        let op = "PhotosFullScan"
        DataSourceDebug.start(op)
        do {
            let count = try await indexAssets(
                modifiedAfter: nil,
                fetchLimit: nil,
                in: context
            )

            defaults.set(
                nowProvider(),
                forKey: Self.incrementalCursorKey
            )

            DataSourceDebug.success(op, count: count)
            return count
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
    }

    // MARK: - Import/Refresh

    @MainActor
    func indexAllPhotos(in context: ModelContext) async throws -> Int {
        try await fullScan(in: context)
    }

    @MainActor
    func indexRecentPhotos(since date: Date, in context: ModelContext) async throws -> Int {
        try await indexAssets(
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
}
