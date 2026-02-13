import Foundation
import SwiftData

struct NotesStoreService {
    private let memoryService: MemoryService?
    private let modelContext: ModelContext?

    init(memoryService: MemoryService) {
        self.memoryService = memoryService
        self.modelContext = nil
    }

    init(context: ModelContext) {
        self.memoryService = nil
        self.modelContext = context
    }

    private func context() -> ModelContext {
        if let modelContext {
            return modelContext
        }
        if let memoryService {
            return memoryService.context()
        }
        fatalError("NotesStoreService saknar ModelContext och MemoryService.")
    }

    func createNote(title: String, body: String, source: String = "user") throws -> UserNote {
        let context = context()
        let note = UserNote(
            title: title,
            body: body,
            source: source,
            externalRef: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        context.insert(note)
        try context.save()
        return note
    }

    func upsertImportedNote(
        title: String,
        body: String,
        source: String,
        externalRef: String
    ) throws -> UserNote {
        let context = context()

        let descriptor = FetchDescriptor<UserNote>(
            predicate: #Predicate { $0.externalRef == externalRef }
        )

        let note: UserNote
        if let existing = try context.fetch(descriptor).first {
            note = existing
            note.title = title
            note.body = body
            note.source = source
            note.externalRef = externalRef
            note.updatedAt = Date()
        } else {
            note = UserNote(
                title: title,
                body: body,
                source: source,
                externalRef: externalRef,
                createdAt: Date(),
                updatedAt: Date()
            )
            context.insert(note)
        }

        try context.save()
        return note
    }

    func listNotes() throws -> [UserNote] {
        let context = context()
        let descriptor = FetchDescriptor<UserNote>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try context.fetch(descriptor)
    }

    func deleteNote(id: String) throws {
        let context = context()
        let descriptor = FetchDescriptor<UserNote>(predicate: #Predicate { $0.id == id })
        guard let note = try context.fetch(descriptor).first else { return }
        context.delete(note)
        try context.save()
    }

    func exportUnifiedItems(in range: DateInterval?) throws -> [UnifiedItemDTO] {
        let notes = try listNotes().filter { note in
            guard let range else { return true }
            return range.contains(note.updatedAt)
        }

        return notes.map { note in
            UnifiedItemDTO(
                id: "note:\(note.id)",
                source: "notes",
                type: .note,
                title: note.title,
                body: note.body,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                startAt: nil,
                endAt: nil,
                dueAt: nil,
                status: [
                    "note_source": AnyCodable(note.source),
                    "external_ref": AnyCodable(note.externalRef ?? "")
                ]
            )
        }
    }
}
