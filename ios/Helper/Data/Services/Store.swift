//
//  Store.swift
//  Helper
//
//  Created by Saga Lilja on 2026-02-14.
//

import Foundation
import SwiftData

// MARK: - Notes Store

struct NotesStore {

    func createNote(
        title: String,
        body: String,
        source: String = "user",
        in context: ModelContext
    ) throws -> UserNote {

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
        externalRef: String,
        in context: ModelContext
    ) throws -> UserNote {

        let descriptor = FetchDescriptor<UserNote>(
            predicate: #Predicate { $0.externalRef == externalRef }
        )

        if let existing = try context.fetch(descriptor).first {

            existing.title = title
            existing.body = body
            existing.source = source
            existing.externalRef = externalRef
            existing.updatedAt = Date()

            try context.save()
            return existing
        }

        let note = UserNote(
            title: title,
            body: body,
            source: source,
            externalRef: externalRef,
            createdAt: Date(),
            updatedAt: Date()
        )

        context.insert(note)
        try context.save()

        return note
    }

    func listNotes(
        in context: ModelContext
    ) throws -> [UserNote] {

        let descriptor = FetchDescriptor<UserNote>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        return try context.fetch(descriptor)
    }

    func deleteNote(
        id: String,
        in context: ModelContext
    ) throws {

        let descriptor = FetchDescriptor<UserNote>(
            predicate: #Predicate { $0.id == id }
        )

        guard let note = try context.fetch(descriptor).first else { return }

        context.delete(note)
        try context.save()
    }
}
// MARK: - Source Checkpoint Store

struct SourceCheckpointStore {

    func lastCheckpoint(
        for source: QuerySource,
        in context: ModelContext
    ) throws -> Date? {

        let descriptor = FetchDescriptor<Etapp2IngestCheckpoint>(
            predicate: #Predicate { $0.source == source.rawValue }
        )

        return try context.fetch(descriptor).first?.lastIngestAt
    }

    func updateCheckpoint(
        for source: QuerySource,
        at date: Date,
        in context: ModelContext
    ) throws {

        let descriptor = FetchDescriptor<Etapp2IngestCheckpoint>(
            predicate: #Predicate { $0.source == source.rawValue }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.lastIngestAt = date
        } else {
            context.insert(
                Etapp2IngestCheckpoint(
                    source: source.rawValue,
                    lastIngestAt: date
                )
            )
        }

        try context.save()
    }
}
