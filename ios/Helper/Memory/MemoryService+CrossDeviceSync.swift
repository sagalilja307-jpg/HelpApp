import Foundation
import SwiftData

struct UserNoteSyncRecord: Codable, Sendable {
    let id: String
    let title: String
    let body: String
    let source: String
    let externalRef: String?
    let createdAt: Date
    let updatedAt: Date
}

extension MemoryService {
    func exportUserNoteSyncRecords() -> [UserNoteSyncRecord] {
        let context = context()
        let descriptor = FetchDescriptor<UserNote>(
            sortBy: [SortDescriptor(\UserNote.updatedAt, order: .reverse)]
        )

        guard let notes = try? context.fetch(descriptor) else {
            return []
        }

        return notes.map { note in
            UserNoteSyncRecord(
                id: note.id,
                title: note.title,
                body: note.body,
                source: note.source,
                externalRef: note.externalRef,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt
            )
        }
    }

    @discardableResult
    func mergeUserNoteSyncRecords(_ records: [UserNoteSyncRecord]) -> Int {
        guard !records.isEmpty else { return 0 }

        let context = context()
        guard let existingNotes = try? context.fetch(FetchDescriptor<UserNote>()) else {
            return 0
        }

        var existingByID: [String: UserNote] = [:]
        existingByID.reserveCapacity(existingNotes.count)
        for note in existingNotes {
            existingByID[note.id] = note
        }

        var mergedCount = 0

        for record in records {
            if let existing = existingByID[record.id] {
                guard record.updatedAt > existing.updatedAt else {
                    continue
                }
                existing.title = record.title
                existing.body = record.body
                existing.source = record.source
                existing.externalRef = record.externalRef
                existing.createdAt = record.createdAt
                existing.updatedAt = record.updatedAt
                mergedCount += 1
                continue
            }

            let note = UserNote(
                id: record.id,
                title: record.title,
                body: record.body,
                source: record.source,
                externalRef: record.externalRef,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
            context.insert(note)
            existingByID[record.id] = note
            mergedCount += 1
        }

        if mergedCount > 0 {
            try? context.save()
        }

        return mergedCount
    }
}
