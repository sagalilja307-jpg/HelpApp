import Foundation
import SwiftData

protocol Etapp2IngestCheckpointStoring: Sendable {
    func lastCheckpoint(for source: QuerySource) throws -> Date?
    func updateCheckpoint(for source: QuerySource, at date: Date) throws
}

struct NoOpEtapp2IngestCheckpointStore: Etapp2IngestCheckpointStoring {
    func lastCheckpoint(for source: QuerySource) throws -> Date? { nil }
    func updateCheckpoint(for source: QuerySource, at date: Date) throws {}
}

struct Etapp2IngestCheckpointStore: Etapp2IngestCheckpointStoring {
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

    func lastCheckpoint(for source: QuerySource) throws -> Date? {
        guard source.isStage2Source else { return nil }

        let context = context()
        let key = source.rawValue
        let descriptor = FetchDescriptor<Etapp2IngestCheckpoint>(
            predicate: #Predicate { $0.source == key }
        )
        return try context.fetch(descriptor).first?.lastIngestAt
    }

    func updateCheckpoint(for source: QuerySource, at date: Date) throws {
        guard source.isStage2Source else { return }

        let context = context()
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

    private func context() -> ModelContext {
        if let modelContext {
            return modelContext
        }
        if let memoryService {
            return memoryService.context()
        }
        fatalError("Etapp2IngestCheckpointStore saknar ModelContext och MemoryService.")
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
