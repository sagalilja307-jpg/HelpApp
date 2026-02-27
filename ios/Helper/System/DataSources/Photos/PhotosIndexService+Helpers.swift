import Foundation
import SwiftData
#if canImport(Photos)
@preconcurrency import Photos
#endif
#if canImport(UIKit)
@preconcurrency import UIKit
#endif

// MARK: - Helpers

extension PhotosIndexService {

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

    @MainActor
    func indexAssets(
        localIdentifiers: [String],
        in context: ModelContext
    ) async throws -> Int {
        #if canImport(Photos)
        let filteredIdentifiers = Array(Set(localIdentifiers.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }))

        guard !filteredIdentifiers.isEmpty else { return 0 }

        let assetsResult = PHAsset.fetchAssets(
            withLocalIdentifiers: filteredIdentifiers,
            options: nil
        )
        guard assetsResult.count > 0 else { return 0 }

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

        return try upsertSnapshots(snapshots, in: context)
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
}
