//
//  HelperApp.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-24.
//

import SwiftUI
import SwiftData

@main
struct HelperApp: App {

    // MARK: - Core services

    private let memoryService: MemoryService
    private let modelContext: ModelContext
    
    // MARK: - Coordinators
    
    private let memoryCoordinator: MemoryCoordinator
    private let decisionLogger: DecisionLogger
    private let safetyCoordinator: SafetyCoordinator
    private let suggestionCoordinator: DecisionCoordinator
    
    // MARK: - Other services
    
    private let queryPipeline: QueryPipeline
    private let supportSettingsService: SupportSettingsAPIService
    private let shareImportService: ShareImportService
    private let sourceConnectionStore: SourceConnectionStore
    private let photosIndexService: PhotosIndexService
    private let filesImportService: FilesImportService
    private let locationSnapshotService: LocationSnapshotService
    private let longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator

    // Onboarding flag (sparas i UserDefaults)
    @AppStorage("helper.onboarding.done") private var onboardingDone = false

    // MARK: - Init

    init() {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        do {
            // 1️⃣ Initiera MemoryService (root dependency)
            let service = try MemoryService(inMemory: isRunningTests)
            self.memoryService = service

            // 2️⃣ Skapa ModelContext för SwiftUI environment
            let context = service.context()
            self.modelContext = context
            
            // 3️⃣ Skapa Coordinators
            let memCoord = MemoryCoordinator(memoryService: service)
            self.memoryCoordinator = memCoord
            
            let sourceConnectionStore = SourceConnectionStore.shared
            self.sourceConnectionStore = sourceConnectionStore
            
            let fileTextExtraction = FileTextExtractionService()
            
            let logger = DecisionLogger(memoryService: service)
            self.decisionLogger = logger
            
            let safetyCoord = SafetyCoordinator(memoryService: service)
            self.safetyCoordinator = safetyCoord

            let coordinator = DecisionCoordinator(decisionLogger: logger)
            self.suggestionCoordinator = coordinator

            // 4️⃣ Skapa QueryPipeline (needs refactoring, but keep for now)
            let access = QuerySourceAccess(sourceConnectionStore: sourceConnectionStore)
            let contactsCollector = ContactsCollectorService()
            let photosIndexService = PhotosIndexService(
                sourceConnectionStore: sourceConnectionStore
            )
            let filesImportService = FilesImportService(
                textExtractionService: fileTextExtraction,
                sourceConnectionStore: sourceConnectionStore
            )
            let locationSnapshotService = LocationSnapshotService()
            let locationCollector = LocationCollectorService(
                snapshotService: locationSnapshotService
            )
            let fetcher = QueryDataFetcher(
                memoryService: service,
                contactsCollector: contactsCollector,
                photosIndexService: photosIndexService,
                filesImportService: filesImportService,
                locationCollector: locationCollector,
                sourceConnectionStore: sourceConnectionStore
            )
            let mailQueryFetcher = MailQueryFetcher(memoryService: service)
            let backendQueryService = BackendQueryAPIService.shared
            let memoryProcessingAPIService = MemoryProcessingAPIService.shared
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
            let longTermMemorySaveCoordinator = LongTermMemorySaveCoordinator(
                container: longTermContainer,
                memoryProcessingAPI: memoryProcessingAPIService
            )
            // Adapter: wrap existing QueryDataFetcher and QuerySourceAccess into
            // the smaller interfaces expected by the updated `QueryPipeline`.
            struct AccessAdapter: QuerySourceAccessChecking {
                let access: QuerySourceAccess
                let sourceConnectionStore: SourceConnectionStoring

                func isEnabled(_ source: QuerySource) -> Bool {
                    switch source {
                    case .calendar, .reminders, .contacts, .photos, .files, .location, .mail:
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

            struct LocalCollectorAdapter: LocalQueryCollecting {
                let fetcher: QueryDataFetcher
                let access: QuerySourceAccessing
                let mailFetcher: MailQueryFetcher

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

                    // Restrict collection to the selected source to avoid expensive cross-source indexing.
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
                    case .mail:
                        options = .default
                    }

                    if let tr = timeRange {
                        let data = try await fetcher.collect(in: tr, access: access, options: options)
                        return LocalCollectedResult(entries: data.entries)
                    }

                    // Fallback: map range to days-window (simple 7‑day window for now)
                    let span = options.includeCalendar || options.includeReminders ? 7 : 7
                    let days = max(1, span)
                    let data = try await fetcher.collect(days: days, access: access, options: options)
                    return LocalCollectedResult(entries: data.entries)
                }
            }

            let accessAdapter = AccessAdapter(access: access, sourceConnectionStore: sourceConnectionStore)
            let localCollectorAdapter = LocalCollectorAdapter(
                fetcher: fetcher,
                access: access,
                mailFetcher: mailQueryFetcher
            )

            self.queryPipeline = QueryPipeline(
                backendQueryService: backendQueryService,
                localCollector: localCollectorAdapter,
                accessGate: accessAdapter
            )
            
            // 5️⃣ Other services
            self.photosIndexService = photosIndexService
            self.filesImportService = filesImportService
            self.locationSnapshotService = locationSnapshotService
            self.longTermMemorySaveCoordinator = longTermMemorySaveCoordinator
            
            let supportSettingsService = SupportSettingsAPIService.shared
            self.supportSettingsService = supportSettingsService
            
            let notesStoreService = NotesStoreService()
            let shareImportService = ShareImportService(
                memoryService: service,
                notesStore: notesStoreService
            )
            self.shareImportService = shareImportService

            if !isRunningTests {
                Task {
                    await supportSettingsService.syncSupportSettingsCache()
                    await longTermMemorySaveCoordinator.processPendingJobs()
                    _ = try? shareImportService.importPendingSharedItems()
                }
            }

        } catch {
            fatalError("Failed to initialize HelperApp core services: \(error)")
        }
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {

            NavigationStack {

                if onboardingDone {

                    ChatView(
                        pipeline: queryPipeline,
                        sourceConnectionStore: sourceConnectionStore,
                        photosIndexService: photosIndexService,
                        filesImportService: filesImportService,
                        locationSnapshotService: locationSnapshotService,
                        longTermMemorySaveCoordinator: longTermMemorySaveCoordinator
                    )

                } else {

                    OnboardingView(onboardingComplete: $onboardingDone)

                }
            }
            .environment(\.modelContext, modelContext)
        }
    }

}
