import Foundation
import SwiftData

enum LongTermMemoryPendingJobStatus: String, Sendable {
    case pending
    case processing
    case failed
}

@Model
final class LongTermMemoryPendingJob {
    @Attribute(.unique)
    var id: UUID

    var text: String
    var language: String
    var attemptCount: Int
    var nextRetryAt: Date
    var lastError: String?
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date
    var lastAttemptAt: Date?

    init(
        text: String,
        language: String,
        now: Date
    ) {
        self.id = UUID()
        self.text = text
        self.language = language
        self.attemptCount = 0
        self.nextRetryAt = now
        self.lastError = nil
        self.statusRaw = LongTermMemoryPendingJobStatus.pending.rawValue
        self.createdAt = now
        self.updatedAt = now
        self.lastAttemptAt = nil
    }

    var status: LongTermMemoryPendingJobStatus {
        get { LongTermMemoryPendingJobStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}
