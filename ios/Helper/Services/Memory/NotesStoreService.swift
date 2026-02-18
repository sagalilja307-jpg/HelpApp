import Foundation
import SwiftData

struct NotesStoreService {

    // MARK: - Create

    func createNote(
        title: String,
        body: String,
        source: String = "user",
        in context: ModelContext
    ) throws -> UserNote {
        let now = DateService.shared.now()

        let note = UserNote(
            title: title,
            body: body,
            source: source,
            externalRef: nil,
            createdAt: now,
            updatedAt: now
        )

        context.insert(note)
        try context.save()

        return note
    }

    // MARK: - Upsert Imported

    func upsertImportedNote(
        title: String,
        body: String,
        source: String,
        externalRef: String,
        in context: ModelContext
    ) throws -> UserNote {

        var descriptor = FetchDescriptor<UserNote>(
            predicate: #Predicate { $0.externalRef == externalRef }
        )
        descriptor.fetchLimit = 1

        let note: UserNote

        if let existing = try context.fetch(descriptor).first {
            note = existing
            note.title = title
            note.body = body
            note.source = source
            note.externalRef = externalRef
            note.updatedAt = DateService.shared.now()
        } else {
            let now = DateService.shared.now()
            note = UserNote(
                title: title,
                body: body,
                source: source,
                externalRef: externalRef,
                createdAt: now,
                updatedAt: now
            )
            context.insert(note)
        }

        try context.save()
        return note
    }

    // MARK: - List

    func listNotes(
        in context: ModelContext
    ) throws -> [UserNote] {

        let descriptor = FetchDescriptor<UserNote>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        return try context.fetch(descriptor)
    }

    // MARK: - Delete

    func deleteNote(
        _ note: UserNote,
        in context: ModelContext
    ) throws {
        context.delete(note)
        try context.save()
    }

    func deleteNote(
        id: String,
        in context: ModelContext
    ) throws {

        var descriptor = FetchDescriptor<UserNote>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        guard let note = try context.fetch(descriptor).first else {
            return
        }

        context.delete(note)
        try context.save()
    }
    
    // MARK: - Search
    
    func searchNotesByKeyword(
        _ keyword: String,
        in context: ModelContext
    ) throws -> [UserNote] {
        let lowercased = keyword.lowercased()
        let descriptor = FetchDescriptor<UserNote>(
            predicate: #Predicate { note in
                note.title.localizedStandardContains(lowercased) ||
                note.body.localizedStandardContains(lowercased)
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Export

    func exportUnifiedItems(
        in range: DateInterval?,
        context: ModelContext
    ) throws -> [UnifiedItemDTO] {

        let notes = try listNotes(in: context).filter { note in
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
