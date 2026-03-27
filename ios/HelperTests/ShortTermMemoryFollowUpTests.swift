import XCTest
@testable import Helper

@MainActor
final class ShortTermMemoryFollowUpTests: XCTestCase {
    private var memoryService: MemoryService!
    private var defaults: UserDefaults!
    private var sourceStore: SourceConnectionStore!
    private var suiteName: String!
    private var storeDirectory: URL!
    private static var retainedServices: [MemoryService] = []
    private static var retainedStoreDirectories: [URL] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortTermMemoryFollowUpTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        memoryService = try MemoryService(
            storeURL: storeDirectory.appendingPathComponent("memory.sqlite")
        )
        Self.retainedServices.append(memoryService)
        Self.retainedStoreDirectories.append(storeDirectory)
        suiteName = "ShortTermMemoryFollowUpTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        sourceStore = SourceConnectionStore(defaults: defaults)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        memoryService = nil
        defaults = nil
        sourceStore = nil
        suiteName = nil
        storeDirectory = nil
        try super.tearDownWithError()
    }

    func testLoadWorkingDayShowsTodayAndOverdueFollowUps() async throws {
        let now = Self.fixedNow
        let coordinator = ShortTermMemoryCoordinator(
            memoryService: memoryService,
            nowProvider: { now }
        )
        let settings = MemorySourceSettings(
            defaults: defaults,
            sourceConnectionStore: sourceStore
        )

        try seedFollowUps(now: now)

        let dayData = await coordinator.loadWorkingDay(now, using: settings)

        XCTAssertEqual(dayData.followUps.count, 2)
        XCTAssertEqual(dayData.followUps.map(\.title), ["Överduen", "Idag"])
    }

    func testLoadWorkingDayShowsOnlyMatchingFutureFollowUps() async throws {
        let now = Self.fixedNow
        let coordinator = ShortTermMemoryCoordinator(
            memoryService: memoryService,
            nowProvider: { now }
        )
        let settings = MemorySourceSettings(
            defaults: defaults,
            sourceConnectionStore: sourceStore
        )

        try seedFollowUps(now: now)
        let futureDate = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now

        let dayData = await coordinator.loadWorkingDay(futureDate, using: settings)

        XCTAssertEqual(dayData.followUps.count, 1)
        XCTAssertEqual(dayData.followUps.first?.title, "Imorgon")
    }

    private func seedFollowUps(now: Date) throws {
        let context = memoryService.context()
        let waitingSince = now.addingTimeInterval(-24 * 60 * 60)
        let eligibleAt = waitingSince.addingTimeInterval(24 * 60 * 60)

        _ = try memoryService.createPendingFollowUp(
            actor: .user,
            sourceMessageID: "one",
            title: "Överduen",
            contextText: "Försenad",
            draftText: "Hej igen!",
            waitingSince: waitingSince,
            eligibleAt: eligibleAt,
            dueAt: now.addingTimeInterval(-60 * 60),
            in: context
        )

        _ = try memoryService.createPendingFollowUp(
            actor: .user,
            sourceMessageID: "two",
            title: "Idag",
            contextText: "Dags idag",
            draftText: "Hej idag!",
            waitingSince: waitingSince,
            eligibleAt: eligibleAt,
            dueAt: now.addingTimeInterval(2 * 60 * 60),
            in: context
        )

        _ = try memoryService.createPendingFollowUp(
            actor: .user,
            sourceMessageID: "three",
            title: "Imorgon",
            contextText: "Dags imorgon",
            draftText: "Hej imorgon!",
            waitingSince: waitingSince,
            eligibleAt: eligibleAt,
            dueAt: now.addingTimeInterval(24 * 60 * 60),
            in: context
        )
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_742_428_800)
}
