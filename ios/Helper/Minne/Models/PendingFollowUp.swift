import Foundation
import SwiftData

public enum PendingFollowUpState: String, Codable, Sendable, CaseIterable {
    case scheduled
    case snoozed
    case completed
    case cancelled

    public var isActive: Bool {
        switch self {
        case .scheduled, .snoozed:
            return true
        case .completed, .cancelled:
            return false
        }
    }
}

@Model
public final class PendingFollowUp {
    @Attribute(.unique) public var id: String
    public var sourceMessageID: String
    public var clusterID: String?
    public var title: String
    public var contextText: String
    public var draftText: String
    public var createdAt: Date
    public var waitingSince: Date
    public var eligibleAt: Date
    public var dueAt: Date
    public var state: PendingFollowUpState
    public var lastNotificationAt: Date?
    public var snoozedUntil: Date?
    public var completedAt: Date?

    public init(
        id: String,
        sourceMessageID: String,
        clusterID: String? = nil,
        title: String,
        contextText: String,
        draftText: String,
        createdAt: Date = DateService.shared.now(),
        waitingSince: Date,
        eligibleAt: Date,
        dueAt: Date,
        state: PendingFollowUpState = .scheduled,
        lastNotificationAt: Date? = nil,
        snoozedUntil: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.sourceMessageID = sourceMessageID
        self.clusterID = clusterID
        self.title = title
        self.contextText = contextText
        self.draftText = draftText
        self.createdAt = createdAt
        self.waitingSince = waitingSince
        self.eligibleAt = eligibleAt
        self.dueAt = dueAt
        self.state = state
        self.lastNotificationAt = lastNotificationAt
        self.snoozedUntil = snoozedUntil
        self.completedAt = completedAt
    }
}

struct PendingFollowUpSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let sourceMessageID: String
    let clusterID: String?
    let title: String
    let contextText: String
    let draftText: String
    let createdAt: Date
    let waitingSince: Date
    let eligibleAt: Date
    let dueAt: Date
    let state: PendingFollowUpState
    let lastNotificationAt: Date?
    let snoozedUntil: Date?
    let completedAt: Date?

    var isActive: Bool {
        state.isActive
    }

    var notificationIdentifier: String {
        "pending-follow-up.\(id)"
    }
}

extension PendingFollowUp {
    var snapshot: PendingFollowUpSnapshot {
        PendingFollowUpSnapshot(
            id: id,
            sourceMessageID: sourceMessageID,
            clusterID: clusterID,
            title: title,
            contextText: contextText,
            draftText: draftText,
            createdAt: createdAt,
            waitingSince: waitingSince,
            eligibleAt: eligibleAt,
            dueAt: dueAt,
            state: state,
            lastNotificationAt: lastNotificationAt,
            snoozedUntil: snoozedUntil,
            completedAt: completedAt
        )
    }
}
