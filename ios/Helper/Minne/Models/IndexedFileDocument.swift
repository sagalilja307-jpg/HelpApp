import Foundation
import SwiftData

@Model
public final class IndexedFileDocument {
    @Attribute(.unique)
    public var id: String

    public var stableHash: String
    public var fileName: String
    public var bodySnippet: String
    public var uti: String
    public var sizeBytes: Int
    public var bookmarkData: Data?
    public var source: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        stableHash: String,
        fileName: String,
        bodySnippet: String,
        uti: String,
        sizeBytes: Int,
        bookmarkData: Data?,
        source: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.stableHash = stableHash
        self.fileName = fileName
        self.bodySnippet = bodySnippet
        self.uti = uti
        self.sizeBytes = sizeBytes
        self.bookmarkData = bookmarkData
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
