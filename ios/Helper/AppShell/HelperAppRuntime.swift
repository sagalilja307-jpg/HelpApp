import Foundation
import SwiftData

struct HelperAppLegacyRuntime {
    let memoryCoordinator: MemoryCoordinator
    let decisionLogger: DecisionLogger
    let safetyCoordinator: SafetyCoordinator
    let suggestionCoordinator: DecisionCoordinator
}

struct HelperAppRuntime {
    let memoryService: MemoryService
    let modelContext: ModelContext
    let legacy: HelperAppLegacyRuntime
    let queryPipeline: QueryPipeline
    let actionSuggestionDetector: HeuristicActionSuggestionDetector
    let actionExecutionCoordinator: ActionExecutionCoordinator
    let chatSuggestionLogger: ChatSuggestionLogger
    let chatSuggestionActionCoordinator: ChatSuggestionActionCoordinator
    let followUpNotificationCoordinator: FollowUpNotificationCoordinator
    let followUpCoordinator: FollowUpCoordinator
    let supportSettingsService: SupportSettingsAPIService
    let shareImportService: ShareImportService
    let sourceConnectionStore: SourceConnectionStore
    let photosIndexService: PhotosIndexService
    let filesImportService: FilesImportService
    let locationSnapshotService: LocationSnapshotService
    let longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator
    let iCloudSyncCoordinator: ICloudKeyValueSyncCoordinator
    let iCloudMemorySyncCoordinator: ICloudMemorySyncCoordinator

    func startBackgroundServices() {
        Task {
            iCloudSyncCoordinator.start()
            iCloudMemorySyncCoordinator.startAutoSync()
            await supportSettingsService.syncSupportSettingsCache()
            await longTermMemorySaveCoordinator.processPendingJobs()
            _ = try? shareImportService.importPendingSharedItems()
        }
    }
}

enum HelperAppBootstrap {
    static func build(isRunningTests: Bool) throws -> HelperAppRuntime {
        let memoryService = try MemoryService(inMemory: isRunningTests)
        let modelContext = memoryService.context()

        let sourceConnectionStore = SourceConnectionStore.shared
        let iCloudSyncCoordinator = ICloudKeyValueSyncCoordinator()
        let fileTextExtraction = FileTextExtractionService()

        let decisionLogger = DecisionLogger(memoryService: memoryService)
        let chatSuggestionLogger = ChatSuggestionLogger(memoryService: memoryService)
        let legacy = HelperAppLegacyRuntime(
            memoryCoordinator: MemoryCoordinator(memoryService: memoryService),
            decisionLogger: decisionLogger,
            safetyCoordinator: SafetyCoordinator(memoryService: memoryService),
            suggestionCoordinator: DecisionCoordinator(decisionLogger: decisionLogger)
        )

        let photosIndexService = PhotosIndexService(
            sourceConnectionStore: sourceConnectionStore
        )
        let filesImportService = FilesImportService(
            textExtractionService: fileTextExtraction,
            sourceConnectionStore: sourceConnectionStore
        )
        let locationSnapshotService = LocationSnapshotService()
        let queryPipeline = makeQueryPipeline(
            memoryService: memoryService,
            sourceConnectionStore: sourceConnectionStore,
            photosIndexService: photosIndexService,
            filesImportService: filesImportService,
            locationSnapshotService: locationSnapshotService
        )

        let memoryProcessingAPIService = MemoryProcessingAPIService.shared
        let longTermMemorySaveCoordinator = try makeLongTermMemorySaveCoordinator(
            memoryProcessingAPI: memoryProcessingAPIService,
            isRunningTests: isRunningTests
        )
        let iCloudMemorySyncCoordinator = ICloudMemorySyncCoordinator(
            memoryService: memoryService,
            longTermMemorySaveCoordinator: longTermMemorySaveCoordinator,
            keyValueSyncCoordinator: iCloudSyncCoordinator
        )
        let actionSuggestionDetector = HeuristicActionSuggestionDetector()
        let followUpNotificationCoordinator = FollowUpNotificationCoordinator()
        let followUpCoordinator = FollowUpCoordinator(
            memoryService: memoryService,
            notificationScheduler: followUpNotificationCoordinator,
            logger: chatSuggestionLogger
        )
        let actionExecutionCoordinator = ActionExecutionCoordinator(
            reminderService: ChatSuggestionReminderService(),
            noteService: ChatSuggestionNoteService(),
            memorySyncCoordinator: iCloudMemorySyncCoordinator,
            sourceConnectionStore: sourceConnectionStore,
            followUpCoordinator: followUpCoordinator,
            noteSource: "chat_suggestion"
        )
        let chatSuggestionActionCoordinator = ChatSuggestionActionCoordinator(
            actionCoordinator: actionExecutionCoordinator
        )

        let supportSettingsService = SupportSettingsAPIService.shared
        let shareImportService = ShareImportService(
            memoryService: memoryService,
            notesStore: NotesStoreService()
        )

        return HelperAppRuntime(
            memoryService: memoryService,
            modelContext: modelContext,
            legacy: legacy,
            queryPipeline: queryPipeline,
            actionSuggestionDetector: actionSuggestionDetector,
            actionExecutionCoordinator: actionExecutionCoordinator,
            chatSuggestionLogger: chatSuggestionLogger,
            chatSuggestionActionCoordinator: chatSuggestionActionCoordinator,
            followUpNotificationCoordinator: followUpNotificationCoordinator,
            followUpCoordinator: followUpCoordinator,
            supportSettingsService: supportSettingsService,
            shareImportService: shareImportService,
            sourceConnectionStore: sourceConnectionStore,
            photosIndexService: photosIndexService,
            filesImportService: filesImportService,
            locationSnapshotService: locationSnapshotService,
            longTermMemorySaveCoordinator: longTermMemorySaveCoordinator,
            iCloudSyncCoordinator: iCloudSyncCoordinator,
            iCloudMemorySyncCoordinator: iCloudMemorySyncCoordinator
        )
    }

    private static func makeQueryPipeline(
        memoryService: MemoryService,
        sourceConnectionStore: SourceConnectionStore,
        photosIndexService: PhotosIndexService,
        filesImportService: FilesImportService,
        locationSnapshotService: LocationSnapshotService
    ) -> QueryPipeline {
        let access = QuerySourceAccess(sourceConnectionStore: sourceConnectionStore)
        let contactsCollector = ContactsCollectorService()
        let locationCollector = LocationCollectorService(
            snapshotService: locationSnapshotService
        )
        let fetcher = QueryDataFetcher(
            memoryService: memoryService,
            contactsCollector: contactsCollector,
            photosIndexService: photosIndexService,
            filesImportService: filesImportService,
            locationCollector: locationCollector,
            sourceConnectionStore: sourceConnectionStore
        )
        let mailQueryFetcher = MailQueryFetcher(memoryService: memoryService)
        let healthQueryFetcher = HealthQueryFetcher()

        let accessAdapter = AccessAdapter(
            access: access,
            sourceConnectionStore: sourceConnectionStore
        )
        let localCollectorAdapter = LocalCollectorAdapter(
            fetcher: fetcher,
            access: access,
            mailFetcher: mailQueryFetcher,
            healthFetcher: healthQueryFetcher
        )

        return QueryPipeline(
            backendQueryService: BackendQueryAPIService.shared,
            localCollector: localCollectorAdapter,
            accessGate: accessAdapter
        )
    }

    private static func makeLongTermMemorySaveCoordinator(
        memoryProcessingAPI: MemoryProcessingAPI,
        isRunningTests: Bool
    ) throws -> LongTermMemorySaveCoordinator {
        let longTermSchema = Schema([
            LongTermMemoryItem.self,
            LongTermMemoryPendingJob.self,
        ])
        let longTermConfig: ModelConfiguration
        if isRunningTests {
            longTermConfig = ModelConfiguration(
                schema: longTermSchema,
                isStoredInMemoryOnly: true
            )
        } else {
            let applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let storeURL = applicationSupportURL.appendingPathComponent("long_term_memory.store")
            longTermConfig = ModelConfiguration(
                schema: longTermSchema,
                url: storeURL
            )
        }

        let longTermContainer = try ModelContainer(
            for: longTermSchema,
            configurations: [longTermConfig]
        )
        return LongTermMemorySaveCoordinator(
            container: longTermContainer,
            memoryProcessingAPI: memoryProcessingAPI
        )
    }
}

private struct AccessAdapter: QuerySourceAccessChecking {
    let access: QuerySourceAccess
    let sourceConnectionStore: SourceConnectionStoring

    func isEnabled(_ source: QuerySource) -> Bool {
        switch source {
        case .calendar, .reminders, .contacts, .photos, .files, .location, .mail, .health:
            return sourceConnectionStore.isEnabled(source)
        default:
            return true
        }
    }

    func isAllowed(_ source: QuerySource) -> Bool {
        access.isAllowed(source)
    }

    func deniedMessage(for source: QuerySource) -> String? {
        let reason = access.deniedReason(for: source)
        return reason.isEmpty ? nil : reason
    }
}

private struct LocalCollectorAdapter: LocalQueryCollecting {
    let fetcher: QueryDataFetcher
    let access: QuerySourceAccessing
    let mailFetcher: MailQueryFetcher
    let healthFetcher: HealthQueryFetcher

    func collect(
        source: QuerySource,
        timeRange: DateInterval?,
        intentPlan: BackendIntentPlanDTO,
        userQuery: UserQuery
    ) async throws -> LocalCollectedResult {
        if source == .mail {
            return try await mailFetcher.collect(
                for: intentPlan,
                timeRange: timeRange,
                userQuery: userQuery
            )
        }
        if source == .health {
            return try await healthFetcher.collect(
                for: intentPlan,
                timeRange: timeRange,
                userQuery: userQuery
            )
        }

        let options: QueryCollectionOptions
        switch source {
        case .memory, .rawEvents:
            options = QueryCollectionOptions(
                shouldCaptureLocation: false,
                includeMemory: true,
                includeNotes: true,
                includeCalendar: false,
                includeReminders: false,
                includeContacts: false,
                includePhotos: false,
                includeFiles: false
            )
        case .calendar:
            options = QueryCollectionOptions(
                shouldCaptureLocation: false,
                includeMemory: false,
                includeNotes: false,
                includeCalendar: true,
                includeReminders: false,
                includeContacts: false,
                includePhotos: false,
                includeFiles: false
            )
        case .reminders:
            options = QueryCollectionOptions(
                shouldCaptureLocation: false,
                includeMemory: false,
                includeNotes: false,
                includeCalendar: false,
                includeReminders: true,
                includeContacts: false,
                includePhotos: false,
                includeFiles: false
            )
        case .contacts:
            options = QueryCollectionOptions(
                shouldCaptureLocation: false,
                includeMemory: false,
                includeNotes: false,
                includeCalendar: false,
                includeReminders: false,
                includeContacts: true,
                includePhotos: false,
                includeFiles: false
            )
        case .photos:
            options = QueryCollectionOptions(
                shouldCaptureLocation: false,
                includeMemory: false,
                includeNotes: false,
                includeCalendar: false,
                includeReminders: false,
                includeContacts: false,
                includePhotos: true,
                includeFiles: false
            )
        case .files:
            options = QueryCollectionOptions(
                shouldCaptureLocation: false,
                includeMemory: false,
                includeNotes: false,
                includeCalendar: false,
                includeReminders: false,
                includeContacts: false,
                includePhotos: false,
                includeFiles: true
            )
        case .location:
            options = QueryCollectionOptions(
                shouldCaptureLocation: true,
                includeMemory: false,
                includeNotes: false,
                includeCalendar: false,
                includeReminders: false,
                includeContacts: false,
                includePhotos: false,
                includeFiles: false
            )
        case .health:
            options = .default
        case .mail:
            options = .default
        }

        if let tr = timeRange {
            let data = try await fetcher.collect(in: tr, access: access, options: options)
            return LocalCollectedResult(entries: data.entries)
        }

        let days = max(1, 7)
        let data = try await fetcher.collect(days: days, access: access, options: options)
        return LocalCollectedResult(entries: data.entries)
    }
}
