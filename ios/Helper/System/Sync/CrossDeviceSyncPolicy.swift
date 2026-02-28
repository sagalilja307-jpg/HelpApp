import Foundation
import SwiftData

enum CrossDeviceSyncDecision: Equatable {
    case synced
    case notSynced(reason: String)
}

enum CrossDeviceSyncPolicy {
    /// Every model in `MemorySchemaV3` must have an explicit sync decision.
    /// Keep this list updated whenever the schema changes.
    static let memoryModelDecisions: [String: CrossDeviceSyncDecision] = [
        "RawEvent": .notSynced(reason: "Korttids/arbetsminne byggs live från källor."),
        "Cluster": .notSynced(reason: "Kan återskapas från långtidsminnen."),
        "ClusterItem": .notSynced(reason: "Deriverad relation till kluster."),
        "DecisionLogEntry": .notSynced(reason: "Lokal audit-logg."),
        "BehaviorPattern": .notSynced(reason: "Lokal inlärning i denna version."),
        "SemanticEmbedding": .notSynced(reason: "Kan återskapas vid behov."),
        "ActorRaw": .notSynced(reason: "Intern metadata."),
        "TitleConfidenceRaw": .notSynced(reason: "Intern metadata."),
        "UserNote": .synced,
        "IndexedContact": .notSynced(reason: "Kommer från systemkällor."),
        "IndexedPhotoAsset": .notSynced(reason: "Kommer från systemkällor."),
        "IndexedFileDocument": .notSynced(reason: "Kommer från importerade filer lokalt."),
        "LongTermMemoryItem": .synced,
        "LongTermMemoryPendingJob": .notSynced(reason: "Transient köstatus lokalt."),
    ]

    static var syncedMemoryModelNames: Set<String> {
        Set(memoryModelDecisions.compactMap { key, decision in
            if case .synced = decision {
                return key
            }
            return nil
        })
    }

    static func uncoveredMemoryModels(in schemaModels: [any PersistentModel.Type]) -> [String] {
        let schemaNames = Set(schemaModels.map { String(describing: $0) })
        let decidedNames = Set(memoryModelDecisions.keys)
        return Array(schemaNames.subtracting(decidedNames)).sorted()
    }

    static func staleMemoryPolicyEntries(in schemaModels: [any PersistentModel.Type]) -> [String] {
        let schemaNames = Set(schemaModels.map { String(describing: $0) })
        let decidedNames = Set(memoryModelDecisions.keys)
        return Array(decidedNames.subtracting(schemaNames)).sorted()
    }
}
