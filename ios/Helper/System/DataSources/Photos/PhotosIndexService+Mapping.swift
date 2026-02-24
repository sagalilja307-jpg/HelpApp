import Foundation

extension PhotosIndexService {

    // MARK: - Mapping

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
