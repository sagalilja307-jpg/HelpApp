import Foundation
import UserNotifications

struct FollowUpSchedulePolicy: Sendable, Equatable {
    let waitingInterval: TimeInterval
    let reminderHour: Int
    let reminderMinute: Int
    let calendar: Calendar

    init(
        waitingInterval: TimeInterval = 24 * 60 * 60,
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        calendar: Calendar = .current
    ) {
        self.waitingInterval = waitingInterval
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.calendar = calendar
    }

    func eligibleAt(waitingSince: Date) -> Date {
        waitingSince.addingTimeInterval(waitingInterval)
    }

    func dueAt(waitingSince: Date) -> Date {
        dueAt(after: eligibleAt(waitingSince: waitingSince))
    }

    func dueAt(after date: Date) -> Date {
        let sameDay = calendar.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: date
        ) ?? date

        if sameDay > date {
            return sameDay
        }

        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        return calendar.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: nextDay
        ) ?? nextDay
    }
}

struct FollowUpComposerDraft: Equatable, Sendable {
    let id: String?
    let sourceMessageID: String?
    let clusterID: String?
    let title: String
    let contextText: String
    let draftText: String
    let waitingSince: Date
    let eligibleAt: Date
    let dueAt: Date

    init(
        id: String? = nil,
        sourceMessageID: String? = nil,
        clusterID: String? = nil,
        title: String,
        contextText: String,
        draftText: String,
        waitingSince: Date,
        eligibleAt: Date,
        dueAt: Date
    ) {
        self.id = id
        self.sourceMessageID = sourceMessageID
        self.clusterID = clusterID
        self.title = title
        self.contextText = contextText
        self.draftText = draftText
        self.waitingSince = waitingSince
        self.eligibleAt = eligibleAt
        self.dueAt = dueAt
    }
}

extension FollowUpComposerDraft {
    init(snapshot: PendingFollowUpSnapshot) {
        self.init(
            id: snapshot.id,
            sourceMessageID: snapshot.sourceMessageID,
            clusterID: snapshot.clusterID,
            title: snapshot.title,
            contextText: snapshot.contextText,
            draftText: snapshot.draftText,
            waitingSince: snapshot.waitingSince,
            eligibleAt: snapshot.eligibleAt,
            dueAt: snapshot.dueAt
        )
    }

    init?(suggestionDraft: ChatSuggestionDraft) {
        guard case .followUp(let draft) = suggestionDraft else {
            return nil
        }

        self.init(
            sourceMessageID: nil,
            clusterID: draft.clusterID,
            title: draft.title,
            contextText: draft.contextText,
            draftText: draft.draftText,
            waitingSince: draft.waitingSince,
            eligibleAt: draft.eligibleAt,
            dueAt: draft.dueAt
        )
    }
}

@MainActor
protocol FollowUpNotificationScheduling {
    func scheduleNotification(for followUp: PendingFollowUpSnapshot) async -> Bool
    func cancelNotification(for followUpID: String) async
}

@MainActor
protocol FollowUpCoordinating {
    func saveFollowUpDraft(
        _ draft: FollowUpComposerDraft,
        defaultSourceMessageID: String,
        logMessageID: String?,
        reasons: [String]
    ) async throws -> PendingFollowUpSnapshot
    func markFollowUpCompleted(
        from draft: FollowUpComposerDraft,
        defaultSourceMessageID: String,
        logMessageID: String?,
        reasons: [String]
    ) async throws -> PendingFollowUpSnapshot
    func snoozeFollowUp(id: String) async throws -> PendingFollowUpSnapshot?
    func cancelFollowUp(id: String) async throws -> PendingFollowUpSnapshot?
    func loadActiveFollowUps() async -> [PendingFollowUpSnapshot]
}

enum FollowUpCoordinatorError: LocalizedError, Equatable {
    case missingFollowUp

    var errorDescription: String? {
        switch self {
        case .missingFollowUp:
            return "Uppföljningen kunde inte hittas."
        }
    }
}

@MainActor
protocol FollowUpPermissionChecking {
    func status() async -> AppPermissionStatus
    func requestAccess() async throws -> AppPermissionStatus
}

@MainActor
protocol FollowUpUserNotificationCentering {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

@MainActor
struct PermissionManagerFollowUpPermissionChecker: FollowUpPermissionChecking {
    func status() async -> AppPermissionStatus {
        await PermissionManager.shared.status(for: .notification)
    }

    func requestAccess() async throws -> AppPermissionStatus {
        try await PermissionManager.shared.requestAccess(for: .notification)
    }
}

@MainActor
struct FollowUpUserNotificationCenterAdapter: FollowUpUserNotificationCentering {
    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

@MainActor
final class FollowUpNotificationCoordinator: FollowUpNotificationScheduling {
    private let permissionChecker: FollowUpPermissionChecking
    private let notificationCenter: FollowUpUserNotificationCentering
    private let calendar: Calendar
    private let nowProvider: @Sendable () -> Date

    init(
        permissionChecker: FollowUpPermissionChecking? = nil,
        notificationCenter: FollowUpUserNotificationCentering? = nil,
        calendar: Calendar = .current,
        nowProvider: (@Sendable () -> Date)? = nil
    ) {
        self.permissionChecker = permissionChecker ?? PermissionManagerFollowUpPermissionChecker()
        self.notificationCenter = notificationCenter ?? FollowUpUserNotificationCenterAdapter()
        self.calendar = calendar
        self.nowProvider = nowProvider ?? { Date() }
    }

    func scheduleNotification(for followUp: PendingFollowUpSnapshot) async -> Bool {
        guard followUp.isActive, followUp.dueAt > nowProvider() else {
            return false
        }

        let accessStatus: AppPermissionStatus
        do {
            let currentStatus = await permissionChecker.status()
            if currentStatus == .notDetermined {
                accessStatus = try await permissionChecker.requestAccess()
            } else {
                accessStatus = currentStatus
            }
        } catch {
            return false
        }

        guard accessStatus == .granted else {
            return false
        }

        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [followUp.notificationIdentifier]
        )

        let content = UNMutableNotificationContent()
        content.title = followUp.title
        content.body = followUp.contextText.isEmpty
            ? "Det är dags att följa upp."
            : followUp.contextText
        content.sound = .default

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: followUp.dueAt
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: followUp.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            return true
        } catch {
            return false
        }
    }

    func cancelNotification(for followUpID: String) async {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: ["pending-follow-up.\(followUpID)"]
        )
    }
}

@MainActor
final class FollowUpCoordinator: FollowUpCoordinating {
    private let memoryService: MemoryService
    private let notificationScheduler: FollowUpNotificationScheduling
    private let logger: ChatSuggestionLogging
    private let schedulePolicy: FollowUpSchedulePolicy
    private let nowProvider: @Sendable () -> Date

    init(
        memoryService: MemoryService,
        notificationScheduler: FollowUpNotificationScheduling,
        logger: ChatSuggestionLogging? = nil,
        schedulePolicy: FollowUpSchedulePolicy? = nil,
        nowProvider: (@Sendable () -> Date)? = nil
    ) {
        self.memoryService = memoryService
        self.notificationScheduler = notificationScheduler
        self.logger = logger ?? NoopChatSuggestionLogger()
        self.schedulePolicy = schedulePolicy ?? .init()
        self.nowProvider = nowProvider ?? { Date() }
    }

    func saveFollowUpDraft(
        _ draft: FollowUpComposerDraft,
        defaultSourceMessageID: String,
        logMessageID: String?,
        reasons: [String]
    ) async throws -> PendingFollowUpSnapshot {
        let normalized = normalizedDraft(
            draft,
            defaultSourceMessageID: defaultSourceMessageID
        )
        let wasNew = normalized.id == nil
        let snapshot = try persistDraft(
            normalized,
            defaultSourceMessageID: defaultSourceMessageID
        )
        let scheduled = await scheduleIfNeeded(snapshot)
        if wasNew {
            logger.log(
                action: .scheduled,
                messageID: logMessageID ?? scheduled.id,
                kind: .followUp,
                confidence: nil,
                reasons: reasons
            )
        }
        return scheduled
    }

    func markFollowUpCompleted(
        from draft: FollowUpComposerDraft,
        defaultSourceMessageID: String,
        logMessageID: String?,
        reasons: [String]
    ) async throws -> PendingFollowUpSnapshot {
        let normalized = normalizedDraft(
            draft,
            defaultSourceMessageID: defaultSourceMessageID
        )
        let wasNew = normalized.id == nil
        let snapshot = try persistDraft(
            normalized,
            defaultSourceMessageID: defaultSourceMessageID
        )

        let context = memoryService.context()
        guard let completed = try memoryService.completePendingFollowUp(
            actor: .user,
            id: snapshot.id,
            completedAt: nowProvider(),
            in: context
        ) else {
            throw FollowUpCoordinatorError.missingFollowUp
        }

        await notificationScheduler.cancelNotification(for: completed.id)
        if wasNew {
            logger.log(
                action: .scheduled,
                messageID: logMessageID ?? completed.id,
                kind: .followUp,
                confidence: nil,
                reasons: reasons
            )
        }
        logger.log(
            action: .executed,
            messageID: logMessageID ?? completed.id,
            kind: .followUp,
            confidence: nil,
            reasons: reasons
        )
        return completed
    }

    func snoozeFollowUp(id: String) async throws -> PendingFollowUpSnapshot? {
        let context = memoryService.context()
        guard let existing = try memoryService.listPendingFollowUps(in: context)
            .first(where: { $0.id == id }) else {
            return nil
        }

        let anchorDate = max(nowProvider(), existing.dueAt)
        guard let snapshot = try memoryService.snoozePendingFollowUp(
            actor: .user,
            id: id,
            dueAt: schedulePolicy.dueAt(after: anchorDate),
            in: context
        ) else {
            return nil
        }

        return await scheduleIfNeeded(snapshot)
    }

    func cancelFollowUp(id: String) async throws -> PendingFollowUpSnapshot? {
        let context = memoryService.context()
        let snapshot = try memoryService.cancelPendingFollowUp(
            actor: .user,
            id: id,
            in: context
        )
        await notificationScheduler.cancelNotification(for: id)
        return snapshot
    }

    func loadActiveFollowUps() async -> [PendingFollowUpSnapshot] {
        let context = memoryService.context()
        return (try? memoryService.listPendingFollowUps(in: context))?
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.dueAt == rhs.dueAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.dueAt < rhs.dueAt
            } ?? []
    }
}

private extension FollowUpCoordinator {
    func persistDraft(
        _ draft: FollowUpComposerDraft,
        defaultSourceMessageID: String
    ) throws -> PendingFollowUpSnapshot {
        let context = memoryService.context()

        if let id = draft.id {
            guard let snapshot = try memoryService.updatePendingFollowUpDraft(
                actor: .user,
                id: id,
                title: draft.title,
                contextText: draft.contextText,
                draftText: draft.draftText,
                in: context
            ) else {
                throw FollowUpCoordinatorError.missingFollowUp
            }
            return snapshot
        }

        return try memoryService.createPendingFollowUp(
            actor: .user,
            sourceMessageID: draft.sourceMessageID ?? defaultSourceMessageID,
            clusterID: draft.clusterID,
            title: draft.title,
            contextText: draft.contextText,
            draftText: draft.draftText,
            waitingSince: draft.waitingSince,
            eligibleAt: draft.eligibleAt,
            dueAt: draft.dueAt,
            in: context
        )
    }

    func scheduleIfNeeded(_ snapshot: PendingFollowUpSnapshot) async -> PendingFollowUpSnapshot {
        guard await notificationScheduler.scheduleNotification(for: snapshot) else {
            return snapshot
        }

        let context = memoryService.context()
        return (try? memoryService.markPendingFollowUpNotificationScheduled(
            actor: .system,
            id: snapshot.id,
            scheduledAt: nowProvider(),
            in: context
        )) ?? snapshot
    }

    func normalizedDraft(
        _ draft: FollowUpComposerDraft,
        defaultSourceMessageID: String
    ) -> FollowUpComposerDraft {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextText = draft.contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftText = draft.draftText.trimmingCharacters(in: .whitespacesAndNewlines)

        return FollowUpComposerDraft(
            id: draft.id,
            sourceMessageID: draft.sourceMessageID ?? defaultSourceMessageID,
            clusterID: draft.clusterID,
            title: title.isEmpty ? "Följ upp" : title,
            contextText: contextText,
            draftText: draftText.isEmpty ? defaultDraftText(for: title) : draftText,
            waitingSince: draft.waitingSince,
            eligibleAt: draft.eligibleAt,
            dueAt: draft.dueAt
        )
    }

    func defaultDraftText(for title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            return "Hej! Jag ville bara följa upp mitt tidigare meddelande."
        }
        return "Hej! Jag ville bara följa upp om \(trimmedTitle.lowercased())."
    }
}
