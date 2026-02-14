import Foundation
import SwiftData
#if canImport(PhotoKit)
import PhotoKit
#endif
#if canImport(UIKit)
import UIKit
#endif

protocol PhotosIndexing {
    func indexIncremental() async throws -> Int
    func fullScan() async throws -> Int
    func collectDelta(since: Date?) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry])
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

    private let memoryService: MemoryService?
    private let modelContext: ModelContext?
    private let sourceConnectionStore: SourceConnectionStoring
    private let defaults: UserDefaults
    private let nowProvider: () -> Date

    init(
        memoryService: MemoryService,
        sourceConnectionStore: SourceConnectionStoring = SourceConnectionStore.shared,
        defaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.memoryService = memoryService
        self.modelContext = nil
        self.sourceConnectionStore = sourceConnectionStore
        self.defaults = defaults
        self.nowProvider = nowProvider
    }

    init(
        context: ModelContext,
        sourceConnectionStore: SourceConnectionStoring = SourceConnectionStore.shared,
        defaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.memoryService = nil
        self.modelContext = context
        self.sourceConnectionStore = sourceConnectionStore
        self.defaults = defaults
        self.nowProvider = nowProvider
    }

    func indexIncremental() async throws -> Int {
        let since = defaults.object(forKey: Self.incrementalCursorKey) as? Date
        let count = try await indexAssets(modifiedAfter: since, fetchLimit: 500)
        defaults.set(nowProvider(), forKey: Self.incrementalCursorKey)
        return count
    }

    func fullScan() async throws -> Int {
        let count = try await indexAssets(modifiedAfter: nil, fetchLimit: nil)
        defaults.set(nowProvider(), forKey: Self.incrementalCursorKey)
        return count
    }

    /// Main-actor isolated because mapping helpers (`mapIndexedAsset`, `makeEntry`) are main-actor isolated
    /// and SwiftData fetches often expect usage on the main actor. This avoids warnings about calling
    /// main actor methods from a nonisolated context.
    @MainActor
    func collectDelta(since: Date?) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        let context = context()
        let descriptor = FetchDescriptor<IndexedPhotoAsset>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let rows = try context.fetch(descriptor)
        let filtered = rows.filter { row in
            guard let since else { return true }
            return row.updatedAt > since
        }

        let items = filtered.map(Self.mapIndexedAsset)
        let entries = filtered.map(Self.makeEntry)
        return (items, entries)
    }
}

extension PhotosIndexService {
    static func mapIndexedAsset(_ row: IndexedPhotoAsset) -> UnifiedItemDTO {
        UnifiedItemDTO(
            id: row.id,
            source: "photos",
            type: .photo,
            title: row.title,
            body: row.bodySnippet,
            createdAt: row.assetCreatedAt ?? row.createdAt,
            updatedAt: row.updatedAt,
            startAt: nil,
            endAt: nil,
            dueAt: nil,
            status: [
                "ocr_enabled": AnyCodable(row.ocrEnabled),
                "ocr_state": AnyCodable(row.ocrState),
                "favorite": AnyCodable(row.isFavorite)
            ]
        )
    }

    static func makeEntry(_ row: IndexedPhotoAsset) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(),
            source: .photos,
            title: row.title,
            body: row.bodySnippet.isEmpty ? nil : row.bodySnippet,
            date: row.assetCreatedAt ?? row.updatedAt
        )
    }

    static func makeSnapshot(
        localIdentifier: String,
        assetCreatedAt: Date?,
        assetUpdatedAt: Date?,
        isFavorite: Bool,
        metadataSnippet: String,
        ocrText: String?,
        ocrEnabled: Bool
    ) -> AssetSnapshot {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = assetCreatedAt.map { formatter.string(from: $0) } ?? "okant datum"

        let text = (ocrText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = text.isEmpty ? metadataSnippet : text
        let title = "Bild \(dateString)"
        let state = ocrEnabled ? (text.isEmpty ? "not_found" : "completed") : "disabled"

        return AssetSnapshot(
            localIdentifier: localIdentifier,
            title: title,
            bodySnippet: body,
            assetCreatedAt: assetCreatedAt,
            assetUpdatedAt: assetUpdatedAt,
            isFavorite: isFavorite,
            ocrText: text.isEmpty ? nil : text,
            ocrEnabled: ocrEnabled,
            ocrState: state
        )
    }
}

private extension PhotosIndexService {
    static let incrementalCursorKey = "helper.stage2.photos.last_indexed_at"

    func context() -> ModelContext {
        if let modelContext {
            return modelContext
        }
        if let memoryService {
            return memoryService.context()
        }
        fatalError("PhotosIndexService saknar ModelContext och MemoryService.")
    }

    func indexAssets(modifiedAfter since: Date?, fetchLimit: Int?) async throws -> Int {
        #if canImport(PhotoKit)
        let snapshots = try await fetchSnapshots(modifiedAfter: since, fetchLimit: fetchLimit)
        return try upsertSnapshots(snapshots)
        #else
        return 0
        #endif
    }

    func upsertSnapshots(_ snapshots: [AssetSnapshot]) throws -> Int {
        guard !snapshots.isEmpty else { return 0 }

        let context = context()
        let existing = try context.fetch(FetchDescriptor<IndexedPhotoAsset>())
        var byIdentifier: [String: IndexedPhotoAsset] = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.localIdentifier, $0) }
        )

        let now = nowProvider()
        var changed = 0
        for snapshot in snapshots {
            let rowId = "photo:\(snapshot.localIdentifier)"
            if let row = byIdentifier[snapshot.localIdentifier] {
                let hasChanged = row.title != snapshot.title
                    || row.bodySnippet != snapshot.bodySnippet
                    || row.assetCreatedAt != snapshot.assetCreatedAt
                    || row.assetUpdatedAt != snapshot.assetUpdatedAt
                    || row.isFavorite != snapshot.isFavorite
                    || row.ocrText != snapshot.ocrText
                    || row.ocrEnabled != snapshot.ocrEnabled
                    || row.ocrState != snapshot.ocrState

                if !hasChanged {
                    continue
                }

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

    #if canImport(PhotoKit)
    func fetchSnapshots(modifiedAfter since: Date?, fetchLimit: Int?) async throws -> [AssetSnapshot] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
        if let fetchLimit {
            options.fetchLimit = fetchLimit
        }
        if let since {
            options.predicate = NSPredicate(
                format: "modificationDate > %@ OR creationDate > %@",
                since as NSDate,
                since as NSDate
            )
        }

        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        let ocrEnabled = sourceConnectionStore.isOCREnabled(for: .photos)
        var snapshots: [AssetSnapshot] = []
        snapshots.reserveCapacity(assets.count)

        for asset in assets {
            let metadataSnippet = metadataSnippet(for: asset)
            var ocrText: String?
            if ocrEnabled {
                ocrText = await extractOCRText(for: asset)
            }

            snapshots.append(
                Self.makeSnapshot(
                    localIdentifier: asset.localIdentifier,
                    assetCreatedAt: asset.creationDate,
                    assetUpdatedAt: asset.modificationDate,
                    isFavorite: asset.isFavorite,
                    metadataSnippet: metadataSnippet,
                    ocrText: ocrText,
                    ocrEnabled: ocrEnabled
                )
            )
        }

        return snapshots
    }

    func metadataSnippet(for asset: PHAsset) -> String {
        let created = asset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "okant"
        let favorite = asset.isFavorite ? "ja" : "nej"
        return "Skapad: \(created)\nFavorit: \(favorite)"
    }

    func extractOCRText(for asset: PHAsset) async -> String? {
        #if canImport(UIKit)
        guard let image = await requestImage(for: asset) else { return nil }
        let text = await PhotoOCR.recognize(from: image).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    func requestImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, _ in
                guard let data, let image = UIImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }
    #endif
    #endif
}

