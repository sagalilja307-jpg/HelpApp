import Foundation
import SwiftData

struct LongTermMemorySyncRecord: Codable, Sendable {
    let id: String
    let originalText: String
    let cleanText: String
    let suggestedType: String
    let tags: [String]
    let embedding: [Float]
    let createdAt: Date
    let isUserEdited: Bool
}

struct LongTermMemorySaveCoordinator {

    enum SaveOutcome: Equatable {
        case saved
        case queued
        case failed(String)
    }

    private let container: ModelContainer
    private let memoryProcessingAPI: MemoryProcessingAPI
    private let nowProvider: () -> Date
    private let retryBackoffSeconds: [TimeInterval] = [
        30,
        120,
        600,
        1_800,
        7_200,
        43_200,
    ]

    init(
        container: ModelContainer,
        memoryProcessingAPI: MemoryProcessingAPI,
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        self.container = container
        self.memoryProcessingAPI = memoryProcessingAPI
        self.nowProvider = nowProvider
    }

    func save(text: String, language: String = "sv") async -> SaveOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failed("Kan inte spara tom text.")
        }

        let context = makeContext()
        let now = nowProvider()
        let job = LongTermMemoryPendingJob(
            text: trimmed,
            language: normalizedLanguage(language),
            now: now
        )
        let jobID = job.id

        do {
            context.insert(job)
            try context.save()
        } catch {
            return .failed("Kunde inte skapa save-jobb: \(error.localizedDescription)")
        }

        await processPendingJobs()

        do {
            let readContext = makeContext()
            if let pending = try fetchJob(id: jobID, in: readContext) {
                if pending.status == .failed {
                    return .failed(pending.lastError ?? "Sparande misslyckades.")
                }
                return .queued
            }
            return .saved
        } catch {
            return .queued
        }
    }

    func processPendingJobs() async {
        let context = makeContext()
        let now = nowProvider()
        let dueJobIDs: [UUID]
        do {
            let allJobs = try context.fetch(
                FetchDescriptor<LongTermMemoryPendingJob>(
                    sortBy: [SortDescriptor(\.createdAt, order: .forward)]
                )
            )
            dueJobIDs = allJobs.filter { job in
                job.status != .failed && job.nextRetryAt <= now
            }.map(\.id)
        } catch {
            return
        }

        for jobID in dueJobIDs {
            await attempt(jobID: jobID)
        }
    }

    func loadClusters(preferredClusterCount: Int? = nil) -> [LongTermMemoryCluster] {
        let context = makeContext()
        let service = LongTermMemoryClusteringService()
        return (try? service.loadClusters(in: context, preferredClusterCount: preferredClusterCount)) ?? []
    }

    func loadAllItems(limit: Int? = nil) -> [LongTermMemoryItem] {
        let context = makeContext()
        let descriptor = FetchDescriptor<LongTermMemoryItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let items = try? context.fetch(descriptor) else { return [] }
        guard let limit, limit > 0 else { return items }
        return Array(items.prefix(limit))
    }

    func loadItems(for cluster: LongTermMemoryCluster) -> [LongTermMemoryItem] {
        let allItems = loadAllItems()
        let memberIDs = Set(cluster.memberIDs)
        return allItems.filter { memberIDs.contains($0.id) }
    }

    func exportSyncRecords() -> [LongTermMemorySyncRecord] {
        let context = makeContext()
        let descriptor = FetchDescriptor<LongTermMemoryItem>(
            sortBy: [SortDescriptor(\LongTermMemoryItem.createdAt, order: .reverse)]
        )
        guard let items = try? context.fetch(descriptor) else {
            return []
        }

        return items.map { item in
            LongTermMemorySyncRecord(
                id: item.id.uuidString,
                originalText: item.originalText,
                cleanText: item.cleanText,
                suggestedType: item.suggestedType,
                tags: item.tags,
                embedding: item.embedding,
                createdAt: item.createdAt,
                isUserEdited: item.isUserEdited
            )
        }
    }

    @discardableResult
    func mergeSyncRecords(_ records: [LongTermMemorySyncRecord]) -> Int {
        guard !records.isEmpty else { return 0 }

        let context = makeContext()
        guard let existingItems = try? context.fetch(FetchDescriptor<LongTermMemoryItem>()) else {
            return 0
        }

        var existingIDs: Set<UUID> = Set(existingItems.map(\.id))
        var mergedCount = 0

        for record in records {
            guard let id = UUID(uuidString: record.id) else {
                continue
            }
            guard !existingIDs.contains(id) else {
                continue
            }

            let item = LongTermMemoryItem(
                originalText: record.originalText,
                cleanText: record.cleanText,
                suggestedType: record.suggestedType,
                tags: record.tags,
                embedding: record.embedding
            )
            item.id = id
            item.createdAt = record.createdAt
            item.isUserEdited = record.isUserEdited
            context.insert(item)
            existingIDs.insert(id)
            mergedCount += 1
        }

        if mergedCount > 0 {
            try? context.save()
        }

        return mergedCount
    }

    private func attempt(jobID: UUID) async {
        let context = makeContext()
        guard let job = try? fetchJob(id: jobID, in: context) else {
            return
        }

        let text = job.text
        let language = job.language
        let now = nowProvider()
        job.status = .processing
        job.lastAttemptAt = now
        job.updatedAt = now

        do {
            try context.save()
        } catch {
            return
        }

        do {
            let processed = try await memoryProcessingAPI.processMemory(
                text: text,
                language: language
            )
            guard let liveJob = try fetchJob(id: jobID, in: context) else {
                return
            }
            let item = LongTermMemoryItem(
                originalText: text,
                cleanText: processed.cleanText,
                suggestedType: processed.suggestedType,
                tags: processed.tags,
                embedding: processed.embedding
            )
            context.insert(item)
            context.delete(liveJob)
            try context.save()
        } catch {
            guard let liveJob = try? fetchJob(id: jobID, in: context) else {
                return
            }
            markFailure(for: liveJob, error: error, in: context)
        }
    }

    private func markFailure(
        for job: LongTermMemoryPendingJob,
        error: Error,
        in context: ModelContext
    ) {
        let now = nowProvider()
        job.attemptCount += 1
        job.lastError = error.localizedDescription
        job.updatedAt = now

        let retryable = isRetryable(error: error)
        if retryable && job.attemptCount <= retryBackoffSeconds.count {
            job.status = .pending
            let delay = retryBackoffSeconds[job.attemptCount - 1]
            job.nextRetryAt = now.addingTimeInterval(delay)
        } else {
            job.status = .failed
            job.nextRetryAt = now
        }

        try? context.save()
    }

    private func isRetryable(error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .networkConnectionLost, .notConnectedToInternet, .cannotLoadFromNetwork:
                return true
            default:
                return false
            }
        }

        if let apiError = error as? MemoryProcessingAPIError {
            switch apiError {
            case .serverError(let statusCode, _):
                return statusCode >= 500 || statusCode == 429
            case .invalidBaseURL, .invalidResponse, .decodingFailed:
                return true
            case .encodingFailed:
                return false
            }
        }

        return true
    }

    private func normalizedLanguage(_ language: String) -> String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? "sv" : trimmed
    }

    private func fetchJob(id: UUID, in context: ModelContext) throws -> LongTermMemoryPendingJob? {
        let jobs = try context.fetch(FetchDescriptor<LongTermMemoryPendingJob>())
        return jobs.first(where: { $0.id == id })
    }

    private func makeContext() -> ModelContext {
        ModelContext(container)
    }
}
