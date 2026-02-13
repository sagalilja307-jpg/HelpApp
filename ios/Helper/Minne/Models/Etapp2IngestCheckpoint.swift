import Foundation
import SwiftData

@Model
public final class Etapp2IngestCheckpoint {
    @Attribute(.unique)
    public var source: String
    public var lastIngestAt: Date

    public init(source: String, lastIngestAt: Date) {
        self.source = source
        self.lastIngestAt = lastIngestAt
    }
}
