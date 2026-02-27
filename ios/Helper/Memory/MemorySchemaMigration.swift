import Foundation
import SwiftData

@Model
final class LegacyIngestCheckpoint {
    @Attribute(.unique)
    var source: String
    var lastIngestAt: Date

    init(source: String, lastIngestAt: Date) {
        self.source = source
        self.lastIngestAt = lastIngestAt
    }
}

enum MemorySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            RawEvent.self,
            Cluster.self,
            ClusterItem.self,
            DecisionLogEntry.self,
            BehaviorPattern.self,
            SemanticEmbedding.self,
            ActorRaw.self,
            TitleConfidenceRaw.self,
            UserNote.self,
            IndexedContact.self,
            IndexedPhotoAsset.self,
            IndexedFileDocument.self,
            LegacyIngestCheckpoint.self
        ]
    }
}

enum MemorySchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            RawEvent.self,
            Cluster.self,
            ClusterItem.self,
            DecisionLogEntry.self,
            BehaviorPattern.self,
            SemanticEmbedding.self,
            ActorRaw.self,
            TitleConfidenceRaw.self,
            UserNote.self,
            IndexedContact.self,
            IndexedPhotoAsset.self,
            IndexedFileDocument.self
        ]
    }
}

enum MemorySchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            RawEvent.self,
            Cluster.self,
            ClusterItem.self,
            DecisionLogEntry.self,
            BehaviorPattern.self,
            SemanticEmbedding.self,
            ActorRaw.self,
            TitleConfidenceRaw.self,
            UserNote.self,
            IndexedContact.self,
            IndexedPhotoAsset.self,
            IndexedFileDocument.self,
            LongTermMemoryItem.self,
            LongTermMemoryPendingJob.self
        ]
    }
}

enum MemorySchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MemorySchemaV1.self, MemorySchemaV2.self, MemorySchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: MemorySchemaV1.self,
                toVersion: MemorySchemaV2.self
            ),
            .lightweight(
                fromVersion: MemorySchemaV2.self,
                toVersion: MemorySchemaV3.self
            )
        ]
    }
}
