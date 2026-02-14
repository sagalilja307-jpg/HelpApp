import Foundation
import SwiftData

/// Coordinates memory operations (CRUD, search, audit logs)
/// Owns ModelContext lifecycle - creates fresh context per operation
@MainActor
final class MemoryCoordinator {
    
    private let memoryService: MemoryService
    private let notesService: NotesStoreService
    
    init(memoryService: MemoryService) {
        self.memoryService = memoryService
        self.notesService = NotesStoreService()
    }
    
    // MARK: - User Notes
    
    func createNote(title: String, body: String, source: String = "user") throws -> UserNote {
        let context = memoryService.context()
        return try notesService.createNote(title: title, body: body, source: source, in: context)
    }
    
    func upsertImportedNote(
        title: String,
        body: String,
        source: String,
        externalRef: String
    ) throws -> UserNote {
        let context = memoryService.context()
        return try notesService.upsertImportedNote(
            title: title,
            body: body,
            source: source,
            externalRef: externalRef,
            in: context
        )
    }
    
    func listNotes() throws -> [UserNote] {
        let context = memoryService.context()
        return try notesService.listNotes(in: context)
    }
    
    func searchNotesByKeyword(_ keyword: String) throws -> [UserNote] {
        let context = memoryService.context()
        return try notesService.searchNotesByKeyword(keyword, in: context)
    }
    
    func deleteNote(_ note: UserNote) throws {
        let context = memoryService.context()
        try notesService.deleteNote(note, in: context)
    }
    
    // MARK: - Raw Events
    
    func saveRawEvent(
        type: String,
        payload: String,
        sourceType: String,
        sourceIdentifier: String,
        detectedAt: Date,
        permission: MemoryService.WritePermission
    ) throws {
        let context = memoryService.context()
        try memoryService.saveRawEvent(
            type: type,
            payload: payload,
            sourceType: sourceType,
            sourceIdentifier: sourceIdentifier,
            detectedAt: detectedAt,
            permission: permission,
            in: context
        )
    }
    
    func fetchRecentRawEvents(limit: Int = 100) throws -> [RawEvent] {
        let context = memoryService.context()
        return try memoryService.fetchRecentRawEvents(limit: limit, in: context)
    }
    
    // MARK: - Clusters
    
    func saveCluster(
        title: String,
        description: String?,
        items: [ClusterItem],
        createdBy: MemoryService.WritePermission
    ) throws -> Cluster {
        let context = memoryService.context()
        return try memoryService.saveCluster(
            title: title,
            description: description,
            items: items,
            createdBy: createdBy,
            in: context
        )
    }
    
    func fetchAllClusters() throws -> [Cluster] {
        let context = memoryService.context()
        return try memoryService.fetchAllClusters(in: context)
    }
    
    // MARK: - Decision Logs
    
    func saveDecisionLog(
        queryText: String,
        matchedClusterIds: [UUID],
        matchedNoteIds: [UUID],
        actionDecision: String,
        reasoning: String,
        decidedBy: MemoryService.WritePermission
    ) throws -> DecisionLogEntry {
        let context = memoryService.context()
        return try memoryService.saveDecisionLog(
            queryText: queryText,
            matchedClusterIds: matchedClusterIds,
            matchedNoteIds: matchedNoteIds,
            actionDecision: actionDecision,
            reasoning: reasoning,
            decidedBy: decidedBy,
            in: context
        )
    }
    
    func fetchRecentDecisions(limit: Int = 50) throws -> [DecisionLogEntry] {
        let context = memoryService.context()
        return try memoryService.fetchRecentDecisions(limit: limit, in: context)
    }
    
    // MARK: - Behavior Patterns
    
    func saveBehaviorPattern(
        patternDescription: String,
        observedFrequency: Int,
        lastObservedAt: Date,
        recordedBy: MemoryService.WritePermission
    ) throws -> BehaviorPattern {
        let context = memoryService.context()
        return try memoryService.saveBehaviorPattern(
            patternDescription: patternDescription,
            observedFrequency: observedFrequency,
            lastObservedAt: lastObservedAt,
            recordedBy: recordedBy,
            in: context
        )
    }
    
    func fetchAllBehaviorPatterns() throws -> [BehaviorPattern] {
        let context = memoryService.context()
        return try memoryService.fetchAllBehaviorPatterns(in: context)
    }
    
    // MARK: - Semantic Search
    
    func storeEmbedding(
        entityType: String,
        entityID: UUID,
        embeddingVector: [Double],
        permission: MemoryService.WritePermission
    ) throws {
        let context = memoryService.context()
        try memoryService.storeEmbedding(
            entityType: entityType,
            entityID: entityID,
            embeddingVector: embeddingVector,
            permission: permission,
            in: context
        )
    }
    
    func semanticSearch(
        queryVector: [Double],
        topK: Int = 10,
        entityType: String? = nil
    ) throws -> [(entityID: UUID, entityType: String, similarity: Double)] {
        let context = memoryService.context()
        return try memoryService.semanticSearch(
            queryVector: queryVector,
            topK: topK,
            entityType: entityType,
            in: context
        )
    }
}
