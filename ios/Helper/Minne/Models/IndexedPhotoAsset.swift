import Foundation
import SwiftData

@Model
public final class IndexedPhotoAsset {
    @Attribute(.unique)
    public var id: String

    public var localIdentifier: String
    public var title: String
    public var bodySnippet: String
    public var assetCreatedAt: Date?
    public var assetUpdatedAt: Date?
    public var isFavorite: Bool
    public var ocrText: String?
    public var ocrEnabled: Bool
    public var ocrState: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        localIdentifier: String,
        title: String,
        bodySnippet: String,
        assetCreatedAt: Date? = nil,
        assetUpdatedAt: Date? = nil,
        isFavorite: Bool = false,
        ocrText: String? = nil,
        ocrEnabled: Bool = false,
        ocrState: String = "disabled",
        createdAt: Date = DateService.shared.now(),
        updatedAt: Date = DateService.shared.now()
    ) {
        self.id = id
        self.localIdentifier = localIdentifier
        self.title = title
        self.bodySnippet = bodySnippet
        self.assetCreatedAt = assetCreatedAt
        self.assetUpdatedAt = assetUpdatedAt
        self.isFavorite = isFavorite
        self.ocrText = ocrText
        self.ocrEnabled = ocrEnabled
        self.ocrState = ocrState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
