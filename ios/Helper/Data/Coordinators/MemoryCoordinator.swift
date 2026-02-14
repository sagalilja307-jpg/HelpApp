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
    
    // Raw event operations removed - use MemoryService directly if needed
    
    // MARK: - Clusters
    
    // Cluster operations removed - use MemoryService directly if needed
    
    // MARK: - Decision Logs
    
    // Decision log operations removed - use DecisionLogger coordinator
    
    // MARK: - Behavior Patterns
    
    // Behavior pattern operations removed - use MemoryService directly if needed
    
    // MARK: - Semantic Search
    
    func storeEmbedding(
        entityType: String,
        entityID: UUID,
        embeddingVector: [Double],
        permission: Actor
    ) throws {
        let context = memoryService.context()
        let floatVector = embeddingVector.map { Float($0) }
        try memoryService.putEmbedding(
            actor: permission,
            embeddingId: entityID.uuidString,
            sourceType: entityType,
            sourceId: entityID.uuidString,
            vector: floatVector,
            in: context
        )
    }
}
