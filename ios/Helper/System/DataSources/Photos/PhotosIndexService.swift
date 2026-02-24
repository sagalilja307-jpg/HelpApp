import Foundation
import SwiftData
#if canImport(Photos)
@preconcurrency import Photos
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
        let op = "PhotosCollect"
        DataSourceDebug.start(op)
        do {
            let descriptor = FetchDescriptor<IndexedPhotoAsset>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )

            let rows = try context.fetch(descriptor)

            let filtered = rows.filter { row in
                guard let since else { return true }
                return row.updatedAt > since
            }

            DataSourceDebug.success(op, count: filtered.count)
            return (
                filtered.map(Self.mapIndexedAsset),
                filtered.map(Self.makeEntry)
            )
        } catch {
            DataSourceDebug.failure(op, error)
            throw error
        }
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

        #if canImport(Photos)

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

    #if canImport(Photos)
    func fetchSnapshots(
        modifiedAfter since: Date?,
        fetchLimit: Int?
    ) async throws -> [AssetSnapshot] {
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "modificationDate", ascending: false)
        ]
        if let since {
            options.predicate = NSPredicate(
                format: "modificationDate > %@",
                since as NSDate
            )
        }
        if let fetchLimit {
            options.fetchLimit = fetchLimit
        }

        let assetsResult = PHAsset.fetchAssets(with: .image, options: options)
        guard assetsResult.count > 0 else { return [] }

        var assets: [PHAsset] = []
        assets.reserveCapacity(assetsResult.count)
        assetsResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        let ocrEnabled = sourceConnectionStore.isOCREnabled(for: .photos)
        var snapshots: [AssetSnapshot] = []
        snapshots.reserveCapacity(assets.count)

        for asset in assets {
            snapshots.append(await makeSnapshot(for: asset, ocrEnabled: ocrEnabled))
        }

        return snapshots
    }

    func makeSnapshot(
        for asset: PHAsset,
        ocrEnabled: Bool
    ) async -> AssetSnapshot {
        let ocrText: String?
        let ocrState: String

        if ocrEnabled {
            #if canImport(UIKit)
            if let image = await requestUIImage(for: asset) {
                let recognized = await PhotoOCR.recognize(from: image)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if recognized.isEmpty {
                    ocrText = nil
                    ocrState = "empty"
                } else {
                    ocrText = String(recognized.prefix(2_000))
                    ocrState = "done"
                }
            } else {
                ocrText = nil
                ocrState = "image_unavailable"
            }
            #else
            ocrText = nil
            ocrState = "unavailable"
            #endif
        } else {
            ocrText = nil
            ocrState = "disabled"
        }

        return AssetSnapshot(
            localIdentifier: asset.localIdentifier,
            title: Self.makeTitle(for: asset),
            bodySnippet: Self.makeBodySnippet(for: asset, ocrText: ocrText),
            assetCreatedAt: asset.creationDate,
            assetUpdatedAt: asset.modificationDate ?? asset.creationDate,
            isFavorite: asset.isFavorite,
            ocrText: ocrText,
            ocrEnabled: ocrEnabled,
            ocrState: ocrState
        )
    }

    #if canImport(UIKit)
    func requestUIImage(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, _ in
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: UIImage(data: data))
            }
        }
    }
    #endif

    static func makeTitle(for asset: PHAsset) -> String {
        guard let date = asset.creationDate else { return "Bild" }
        return "Bild \(photoTitleFormatter.string(from: date))"
    }

    static func makeBodySnippet(for asset: PHAsset, ocrText: String?) -> String {
        var parts: [String] = []

        if let date = asset.creationDate {
            parts.append(photoBodyFormatter.string(from: date))
        }

        parts.append("\(asset.pixelWidth)x\(asset.pixelHeight)")

        if asset.isFavorite {
            parts.append("favorit")
        }

        if let ocrText, !ocrText.isEmpty {
            parts.append(String(ocrText.prefix(240)))
        }

        return parts.isEmpty ? "Bild i biblioteket" : parts.joined(separator: " • ")
    }

    static let photoTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let photoBodyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    #endif

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
