import XCTest
@testable import Helper

@MainActor
final class FollowUpCoordinatorTests: XCTestCase {
    private var memoryService: MemoryService!
    private var scheduler: RecordingFollowUpNotificationScheduler!
    private var policy: FollowUpSchedulePolicy!
    private var storeDirectory: URL!
    private static var retainedServices: [MemoryService] = []
    private static var retainedStoreDirectories: [URL] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FollowUpCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        memoryService = try MemoryService(
            storeURL: storeDirectory.appendingPathComponent("memory.sqlite")
        )
        Self.retainedServices.append(memoryService)
        Self.retainedStoreDirectories.append(storeDirectory)
        scheduler = RecordingFollowUpNotificationScheduler()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        policy = FollowUpSchedulePolicy(calendar: calendar)
    }

    override func tearDownWithError() throws {
        memoryService = nil
        scheduler = nil
        policy = nil
        storeDirectory = nil
        try super.tearDownWithError()
    }

    func testSaveFollowUpDraftCreatesPendingFollowUpAndSchedulesNotification() async throws {
        let coordinator = makeCoordinator(now: Self.fixedNow)

        let saved = try await coordinator.saveFollowUpDraft(
            Self.makeDraft(policy: policy, waitingSince: Self.fixedNow),
            defaultSourceMessageID: "assistant-message",
            logMessageID: "assistant-message",
            reasons: ["trigger:user_text"]
        )

        XCTAssertEqual(saved.state, .scheduled)
        XCTAssertEqual(saved.eligibleAt.timeIntervalSince(saved.waitingSince), 24 * 60 * 60, accuracy: 1)
        XCTAssertEqual(saved.dueAt, Date(timeIntervalSince1970: 1_742_547_600))
        XCTAssertEqual(scheduler.scheduledIDs, [saved.id])

        let context = memoryService.context()
        let persisted = try memoryService.listPendingFollowUps(in: context)
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.lastNotificationAt, Self.fixedNow)
    }

    func testSaveFollowUpDraftKeepsFollowUpWhenNotificationSchedulingFails() async throws {
        scheduler.scheduleResult = false
        let coordinator = makeCoordinator(now: Self.fixedNow)

        let saved = try await coordinator.saveFollowUpDraft(
            Self.makeDraft(policy: policy, waitingSince: Self.fixedNow),
            defaultSourceMessageID: "assistant-message",
            logMessageID: "assistant-message",
            reasons: ["trigger:user_text"]
        )

        XCTAssertEqual(saved.state, .scheduled)
        XCTAssertTrue(scheduler.scheduledIDs.isEmpty)

        let context = memoryService.context()
        let persisted = try memoryService.listPendingFollowUps(in: context)
        XCTAssertEqual(persisted.count, 1)
        XCTAssertNil(persisted.first?.lastNotificationAt)
    }

    func testSnoozeFollowUpMovesDueDateToNextNineAfterCurrentDueDate() async throws {
        let coordinator = makeCoordinator(now: Self.fixedNow)

        let saved = try await coordinator.saveFollowUpDraft(
            Self.makeDraft(policy: policy, waitingSince: Self.fixedNow),
            defaultSourceMessageID: "assistant-message",
            logMessageID: "assistant-message",
            reasons: ["trigger:user_text"]
        )
        scheduler.resetScheduled()

        let snoozed = try await coordinator.snoozeFollowUp(id: saved.id)

        XCTAssertEqual(snoozed?.state, .snoozed)
        XCTAssertEqual(snoozed?.dueAt, Date(timeIntervalSince1970: 1_742_634_000))
        XCTAssertEqual(scheduler.scheduledIDs, [saved.id])
    }

    func testMarkFollowUpCompletedCancelsPendingNotification() async throws {
        let coordinator = makeCoordinator(now: Self.fixedNow)

        let saved = try await coordinator.saveFollowUpDraft(
            Self.makeDraft(policy: policy, waitingSince: Self.fixedNow),
            defaultSourceMessageID: "assistant-message",
            logMessageID: "assistant-message",
            reasons: ["trigger:user_text"]
        )

        let completed = try await coordinator.markFollowUpCompleted(
            from: .init(snapshot: saved),
            defaultSourceMessageID: "assistant-message",
            logMessageID: "assistant-message",
            reasons: ["trigger:user_text"]
        )

        XCTAssertEqual(completed.state, .completed)
        XCTAssertEqual(scheduler.cancelledIDs, [saved.id])
    }

    func testCancelFollowUpMarksCancelledAndCancelsNotification() async throws {
        let coordinator = makeCoordinator(now: Self.fixedNow)

        let saved = try await coordinator.saveFollowUpDraft(
            Self.makeDraft(policy: policy, waitingSince: Self.fixedNow),
            defaultSourceMessageID: "assistant-message",
            logMessageID: "assistant-message",
            reasons: ["trigger:user_text"]
        )

        let cancelled = try await coordinator.cancelFollowUp(id: saved.id)

        XCTAssertEqual(cancelled?.state, .cancelled)
        XCTAssertEqual(scheduler.cancelledIDs, [saved.id])
    }

    private func makeCoordinator(now: Date) -> FollowUpCoordinator {
        FollowUpCoordinator(
            memoryService: memoryService,
            notificationScheduler: scheduler,
            schedulePolicy: policy,
            nowProvider: { now }
        )
    }

    private static func makeDraft(
        policy: FollowUpSchedulePolicy,
        waitingSince: Date
    ) -> FollowUpComposerDraft {
        FollowUpComposerDraft(
            title: "Följ upp med Sara",
            contextText: "Väntar på svar från Sara.",
            draftText: "Hej Sara! Jag ville bara följa upp mitt tidigare meddelande.",
            waitingSince: waitingSince,
            eligibleAt: policy.eligibleAt(waitingSince: waitingSince),
            dueAt: policy.dueAt(waitingSince: waitingSince)
        )
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_742_428_800)
}

@MainActor
private final class RecordingFollowUpNotificationScheduler: FollowUpNotificationScheduling {
    var scheduleResult = true
    private(set) var scheduledIDs: [String] = []
    private(set) var cancelledIDs: [String] = []

    func resetScheduled() {
        scheduledIDs.removeAll()
    }

    func scheduleNotification(for followUp: PendingFollowUpSnapshot) async -> Bool {
        if scheduleResult {
            scheduledIDs.append(followUp.id)
        }
        return scheduleResult
    }

    func cancelNotification(for followUpID: String) async {
        cancelledIDs.append(followUpID)
    }
}
