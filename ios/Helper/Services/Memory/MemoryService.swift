import Foundation
import SwiftData

/// MemoryService owns persistence and audit logging.
/// It does NOT own business rules, preferences logic, or decision policy.
public final class MemoryService {

    // MARK: - Permissions

    public struct Permissions: Sendable {
        public let rawEvents = StorePermission(canWrite: [.system])
        public let clusters = StorePermission(canWrite: [.ai, .user])
        public let decisionLog = StorePermission(canWrite: [.system], appendOnly: true)
        public let behaviorPatterns = StorePermission(canWrite: [.system])
    }

    public let container: ModelContainer
    public let permissions = Permissions()

    // MARK: - Init

    public init(
        inMemory: Bool = false,
        storeURL: URL? = nil
    ) throws {
        let schema = Schema(versionedSchema: MemorySchemaV2.self)
        let config: ModelConfiguration

        if inMemory {
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
        } else if let storeURL {
            config = ModelConfiguration(
                schema: schema,
                url: storeURL
            )
        } else {
            config = ModelConfiguration(schema: schema)
        }

        do {
            self.container = try ModelContainer(
                for: schema,
                migrationPlan: MemorySchemaMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            self.container = try ModelContainer(
                for: schema,
                configurations: [config]
            )
        }
    }

    public func context() -> ModelContext {
        ModelContext(container)
    }

    // MARK: - Permission helper

    private func requireWrite(
        _ actor: Actor,
        _ permission: StorePermission,
        store: String
    ) throws {
        guard permission.canWrite.contains(actor) else {
            throw MemoryError.permissionDenied(
                actor: actor,
                store: store
            )
        }
    }

    // MARK: - Semantic Index (storage only)

    public func putEmbedding(
        actor: Actor,
        embeddingId: String,
        sourceType: String,
        sourceId: String,
        vector: [Float],
        in context: ModelContext
    ) throws {
        try requireWrite(actor, StorePermission(canWrite: [.system]), store: "semantic_index.store")

        let data = vector.withUnsafeBufferPointer {
            Data(buffer: UnsafeBufferPointer(start: $0.baseAddress, count: $0.count))
        }

        var descriptor = FetchDescriptor<SemanticEmbedding>(
            predicate: #Predicate { $0.embeddingId == embeddingId }
        )
        descriptor.fetchLimit = 1

        if try context.fetch(descriptor).first == nil {
            context.insert(
                SemanticEmbedding(
                    embeddingId: embeddingId,
                    sourceType: sourceType,
                    sourceId: sourceId,
                    vectorData: data
                )
            )
            try context.save()
        }
    }

    public struct RetrievedMemory {
        public let sourceType: String
        public let sourceId: String
        public let similarity: Float
    }

    public func retrieveRelevantMemories(
        queryVector: [Float],
        threshold: Float = 0.75,
        limit: Int = 5,
        in context: ModelContext
    ) throws -> [RetrievedMemory] {

        let all = try context.fetch(FetchDescriptor<SemanticEmbedding>())
        var scored: [RetrievedMemory] = []

        for emb in all {
            let vector = emb.vectorData.withUnsafeBytes {
                Array(
                    UnsafeBufferPointer<Float>(
                        start: $0.bindMemory(to: Float.self).baseAddress!,
                        count: emb.vectorData.count / MemoryLayout<Float>.size
                    )
                )
            }

            let sim = cosineSimilarity(queryVector, vector)
            if sim >= threshold {
                scored.append(
                    RetrievedMemory(
                        sourceType: emb.sourceType,
                        sourceId: emb.sourceId,
                        similarity: sim
                    )
                )
            }
        }

        return scored
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count)
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        return dot / (sqrt(normA) * sqrt(normB) + 1e-8)
    }

    // MARK: - Raw Events

    public func putRawEvent(
        actor: Actor,
        id: String,
        source: String,
        timestamp: Date,
        payloadJSON: String,
        text: String? = nil,  // 🆕 valfri parameter
        in context: ModelContext
    ) throws {
        try requireWrite(actor, permissions.rawEvents, store: "raw_events.store")

        var descriptor = FetchDescriptor<RawEvent>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.source = source
            existing.timestamp = timestamp
            existing.payloadJSON = payloadJSON
            if let text = text {
                existing.text = text
            }
        } else {
            context.insert(
                RawEvent(
                    id: id,
                    source: source,
                    timestamp: timestamp,
                    payloadJSON: payloadJSON,
                    text: text  // 🆕 sätt texten vid init
                )
            )
        }

        try context.save()
    }

    // MARK: - Decision Log

    public func appendDecision(
        actor: Actor,
        decisionId: String,
        action: DecisionAction,
        reason: [String],
        usedMemory: [String: AnyCodable]? = nil,
        in context: ModelContext
    ) throws {
        try requireWrite(actor, permissions.decisionLog, store: "decision_log.store")

        let reasonJSON = try JSONCodec.encode(reason)
        let usedMemoryJSON = try usedMemory.map { try JSONCodec.encode($0) }

        context.insert(
            DecisionLogEntry(
                decisionId: decisionId,
                action: action.rawValue,
                reasonJSON: reasonJSON,
                usedMemoryJSON: usedMemoryJSON
            )
        )

        try context.save()
    }

    // MARK: - Behavior Patterns

    public func upsertBehaviorPattern(
        actor: Actor,
        pattern: String,
        confidence: Double,
        evidenceJSON: String?,
        in context: ModelContext
    ) throws {
        try requireWrite(actor, permissions.behaviorPatterns, store: "behavior_patterns.store")

        var descriptor = FetchDescriptor<BehaviorPattern>(
            predicate: #Predicate { $0.pattern == pattern }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.confidence = confidence
            existing.evidenceJSON = evidenceJSON
            existing.updatedAt = DateService.shared.now()
        } else {
            context.insert(
                BehaviorPattern(
                    pattern: pattern,
                    confidence: confidence,
                    evidenceJSON: evidenceJSON,
                    updatedAt: DateService.shared.now()
                )
            )
        }

        try context.save()
    }

    // MARK: - Clusters

    private func fetchRawEvents(
        ids: [String],
        in context: ModelContext
    ) throws -> [RawEvent] {
        guard !ids.isEmpty else { return [] }
        let set = Set(ids)
        return try context.fetch(
            FetchDescriptor<RawEvent>(
                predicate: #Predicate { set.contains($0.id) }
            )
        )
    }
    
    private func getRawEvent(
        id: String,
        in context: ModelContext
    ) throws -> RawEvent? {
        var descriptor = FetchDescriptor<RawEvent>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func proposeCluster(
        actor: Actor,
        clusterId: String,
        label: String,
        requiresPrep: RequiresPrep = .unknown,
        confidence: Double = 0.0,
        sourceEventIds: [String] = [],
        in context: ModelContext
    ) throws {
        try requireWrite(actor, permissions.clusters, store: "clusters.store")

        var descriptor = FetchDescriptor<Cluster>(
            predicate: #Predicate { $0.clusterId == clusterId }
        )
        descriptor.fetchLimit = 1

        let cluster = try context.fetch(descriptor).first ?? {
            let c = Cluster(
                clusterId: clusterId,
                label: label,
                requiresPrep: requiresPrep,
                confidence: confidence,
                status: .proposed,
                proposedBy: actor
            )
            context.insert(c)
            return c
        }()

        cluster.label = label
        cluster.requiresPrep = requiresPrep
        cluster.confidence = confidence
        cluster.status = .proposed
        cluster.updatedAt = DateService.shared.now()
        cluster.proposedBy.value = actor.rawValue

        if !sourceEventIds.isEmpty {
            let events = try fetchRawEvents(ids: sourceEventIds, in: context)
            for ev in events {
                context.insert(ClusterItem(cluster: cluster, event: ev))
            }
        }

        try context.save()
    }

    public func activateCluster(
        actor: Actor,
        clusterId: String,
        in context: ModelContext
    ) throws {
        try requireWrite(actor, permissions.clusters, store: "clusters.store")

        guard actor == .user else {
            throw MemoryError.permissionDenied(actor: actor, store: "clusters.activate(user_only)")
        }

        var descriptor = FetchDescriptor<Cluster>(
            predicate: #Predicate { $0.clusterId == clusterId }
        )
        descriptor.fetchLimit = 1

        guard let cluster = try context.fetch(descriptor).first else { return }

        cluster.status = .active
        cluster.updatedAt = DateService.shared.now()
        try context.save()
    }

    // MARK: - Deletion / Maintenance

    public func forgetEvent(
        actor: Actor,
        eventId: String,
        in context: ModelContext
    ) throws {
        try requireWrite(actor, permissions.rawEvents, store: "raw_events.store")

        let items = try context.fetch(
            FetchDescriptor<ClusterItem>(
                predicate: #Predicate { $0.event.id == eventId }
            )
        )

        for item in items {
            context.delete(item)
        }

        if let ev = try getRawEvent(id: eventId, in: context) {
            context.delete(ev)
        }

        try context.save()
    }

    public func purgeAll(
        actor: Actor,
        in context: ModelContext
    ) throws {
        guard actor == .system else {
            throw MemoryError.permissionDenied(actor: actor, store: "purge_all(system_only)")
        }

        // Explicitly fetch and delete for each model type to satisfy generics
        do {
            let rawEvents = try context.fetch(FetchDescriptor<RawEvent>())
            for obj in rawEvents { context.delete(obj) }

            let clusterItems = try context.fetch(FetchDescriptor<ClusterItem>())
            for obj in clusterItems { context.delete(obj) }

            let clusters = try context.fetch(FetchDescriptor<Cluster>())
            for obj in clusters { context.delete(obj) }

            let decisions = try context.fetch(FetchDescriptor<DecisionLogEntry>())
            for obj in decisions { context.delete(obj) }

            let patterns = try context.fetch(FetchDescriptor<BehaviorPattern>())
            for obj in patterns { context.delete(obj) }

            let embeddings = try context.fetch(FetchDescriptor<SemanticEmbedding>())
            for obj in embeddings { context.delete(obj) }

            let actors = try context.fetch(FetchDescriptor<ActorRaw>())
            for obj in actors { context.delete(obj) }

            let titleConfs = try context.fetch(FetchDescriptor<TitleConfidenceRaw>())
            for obj in titleConfs { context.delete(obj) }

            let userNotes = try context.fetch(FetchDescriptor<UserNote>())
            for obj in userNotes { context.delete(obj) }
        }

        try context.save()
    }
}
