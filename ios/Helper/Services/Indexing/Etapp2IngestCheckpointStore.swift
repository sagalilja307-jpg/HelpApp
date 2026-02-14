import Foundation
import SwiftData

protocol Etapp2IngestCheckpointStoring: Sendable {
    func lastCheckpoint(for source: QuerySource, in context: ModelContext) throws -> Date?
    func updateCheckpoint(for source: QuerySource, at date: Date, in context: ModelContext) throws
}

struct NoOpEtapp2IngestCheckpointStore: Etapp2IngestCheckpointStoring {
    func lastCheckpoint(for source: QuerySource, in context: ModelContext) throws -> Date? { nil }
    func updateCheckpoint(for source: QuerySource, at date: Date, in context: ModelContext) throws {}
}

struct Etapp2IngestCheckpointStore: Etapp2IngestCheckpointStoring {

    init() {}

    func lastCheckpoint(for source: QuerySource, in context: ModelContext) throws -> Date? {
        guard source.isStage2Source else { return nil }

        let key = source.rawValue
        let descriptor = FetchDescriptor<Etapp2IngestCheckpoint>(
            predicate: #Predicate { $0.source == key }
        )
        return try context.fetch(descriptor).first?.lastIngestAt
    }

    func updateCheckpoint(for source: QuerySource, at date: Date, in context: ModelContext) throws {
        guard source.isStage2Source else { return }

        let key = source.rawValue
        let descriptor = FetchDescriptor<Etapp2IngestCheckpoint>(
            predicate: #Predicate { $0.source == key }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.lastIngestAt = date
        } else {
            context.insert(Etapp2IngestCheckpoint(source: key, lastIngestAt: date))
        }

        try context.save()
    }
    
    // MARK: - String-based convenience methods
    
    func getLastIngestTimestamp(source: String, in context: ModelContext) throws -> Date? {
        let descriptor = FetchDescriptor<Etapp2IngestCheckpoint>(
            predicate: #Predicate { $0.source == source }
        )
        return try context.fetch(descriptor).first?.lastIngestAt
    }
    
    func updateIngestCheckpoint(source: String, timestamp: Date, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<Etapp2IngestCheckpoint>(
            predicate: #Predicate { $0.source == source }
        )
        
        if let existing = try context.fetch(descriptor).first {
            existing.lastIngestAt = timestamp
        } else {
            context.insert(Etapp2IngestCheckpoint(source: source, lastIngestAt: timestamp))
        }
        
        try context.save()
    }
    
    func getAllCheckpoints(in context: ModelContext) throws -> [Etapp2IngestCheckpoint] {
        let descriptor = FetchDescriptor<Etapp2IngestCheckpoint>(
            sortBy: [SortDescriptor(\.lastIngestAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }
}

private extension QuerySource {
    var isStage2Source: Bool {
        switch self {
        case .contacts, .photos, .files:
            return true
        default:
            return false
        }
    }
}
