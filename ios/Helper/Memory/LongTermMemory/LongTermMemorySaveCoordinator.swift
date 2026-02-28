import Foundation
import SwiftData

struct LongTermMemorySyncRecord: Codable, Sendable {
    let id: String
    let originalText: String
    let cleanText: String
    let cognitiveType: String
    let domain: String
    let actionState: String
    let timeRelation: String
    let tags: [String]
    let embedding: [Float]
    let createdAt: Date
    let updatedAt: Date?
    let isUserEdited: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case originalText
        case cleanText
        case cognitiveType
        case suggestedType
        case domain
        case actionState
        case timeRelation
        case tags
        case embedding
        case createdAt
        case updatedAt
        case isUserEdited
    }

    init(
        id: String,
        originalText: String,
        cleanText: String,
        cognitiveType: String,
        domain: String,
        actionState: String,
        timeRelation: String,
        tags: [String],
        embedding: [Float],
        createdAt: Date,
        updatedAt: Date?,
        isUserEdited: Bool
    ) {
        self.id = id
        self.originalText = originalText
        self.cleanText = cleanText
        self.cognitiveType = cognitiveType
        self.domain = domain
        self.actionState = actionState
        self.timeRelation = timeRelation
        self.tags = tags
        self.embedding = embedding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isUserEdited = isUserEdited
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        originalText = try container.decode(String.self, forKey: .originalText)
        cleanText = try container.decode(String.self, forKey: .cleanText)
        let decodedCognitiveType = try container.decodeIfPresent(String.self, forKey: .cognitiveType)
        let legacySuggestedType = try container.decodeIfPresent(String.self, forKey: .suggestedType)
        cognitiveType = decodedCognitiveType ?? legacySuggestedType ?? "other"
        domain = try container.decodeIfPresent(String.self, forKey: .domain) ?? "other"
        actionState = try container.decodeIfPresent(String.self, forKey: .actionState) ?? "info"
        timeRelation = try container.decodeIfPresent(String.self, forKey: .timeRelation) ?? "none"
        tags = try container.decode([String].self, forKey: .tags)
        embedding = try container.decode([Float].self, forKey: .embedding)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        isUserEdited = try container.decode(Bool.self, forKey: .isUserEdited)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(originalText, forKey: .originalText)
        try container.encode(cleanText, forKey: .cleanText)
        try container.encode(cognitiveType, forKey: .cognitiveType)
        try container.encode(domain, forKey: .domain)
        try container.encode(actionState, forKey: .actionState)
        try container.encode(timeRelation, forKey: .timeRelation)
        try container.encode(tags, forKey: .tags)
        try container.encode(embedding, forKey: .embedding)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encode(isUserEdited, forKey: .isUserEdited)
    }
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
                cognitiveType: item.cognitiveType,
                domain: item.domain,
                actionState: item.actionState,
                timeRelation: item.timeRelation,
                tags: item.tags,
                embedding: item.embedding,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
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
                cognitiveType: record.cognitiveType,
                domain: record.domain,
                actionState: record.actionState,
                timeRelation: record.timeRelation,
                tags: record.tags,
                embedding: record.embedding
            )
            item.id = id
            item.createdAt = record.createdAt
            item.updatedAt = record.updatedAt ?? record.createdAt
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
                cognitiveType: processed.cognitiveType,
                domain: processed.domain,
                actionState: processed.actionState,
                timeRelation: processed.timeRelation,
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
