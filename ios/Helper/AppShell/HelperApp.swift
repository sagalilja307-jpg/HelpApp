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
    private let decisionLogger: DecisionLogger
    private let suggestionCoordinator: SuggestionCoordinator
    private let queryPipeline: QueryPipeline
    private let supportSettingsService: SupportSettingsAPIService
    private let notesStoreService: NotesStoreService
    private let shareImportService: ShareImportService
    private let sourceConnectionStore: SourceConnectionStore
    private let photosIndexService: PhotosIndexService
    private let filesImportService: FilesImportService
    private let locationSnapshotService: LocationSnapshotService

    // Onboarding flag (sparas i UserDefaults)
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    // MARK: - Init

    init() {
        do {
            // 1️⃣ Initiera MemoryService
            let service = try MemoryService()
            self.memoryService = service

            // 2️⃣ Skapa ModelContext
            let context = service.context()
            self.modelContext = context

            // 3️⃣ Skapa DecisionLogger
            let logger = DecisionLogger(
                memoryService: service,
                context: context
            )
            self.decisionLogger = logger

            // 4️⃣ Skapa SuggestionCoordinator
            let coordinator = SuggestionCoordinator(
                decisionLogger: logger
            )
            self.suggestionCoordinator = coordinator

            // 5️⃣ Skapa QueryPipeline
            let sourceConnectionStore = SourceConnectionStore.shared
            self.sourceConnectionStore = sourceConnectionStore

            let access = QuerySourceAccess(sourceConnectionStore: sourceConnectionStore)
            let interpreter = QueryInterpreter()
            let checkpointStore = Etapp2IngestCheckpointStore(memoryService: service)
            let contactsCollector = ContactsCollectorService(memoryService: service)
            let photosIndexService = PhotosIndexService(
                memoryService: service,
                sourceConnectionStore: sourceConnectionStore
            )
            let filesImportService = FilesImportService(
                memoryService: service,
                sourceConnectionStore: sourceConnectionStore
            )
            let locationSnapshotService = LocationSnapshotService(memoryService: service)
            let locationCollector = LocationCollectorService(
                memoryService: service,
                snapshotService: locationSnapshotService
            )
            let fetcher = QueryDataFetcher(
                memoryService: service,
                contactsCollector: contactsCollector,
                photosIndexService: photosIndexService,
                filesImportService: filesImportService,
                locationCollector: locationCollector,
                sourceConnectionStore: sourceConnectionStore,
                checkpointStore: checkpointStore
            )
            let ingestService = AssistantIngestAPIService.shared
            let backendQueryService = BackendQueryAPIService.shared

            self.queryPipeline = QueryPipeline(
                interpreter: interpreter,
                access: access,
                fetcher: fetcher,
                ingestService: ingestService,
                backendQueryService: backendQueryService,
                checkpointStore: checkpointStore,
                sourceConnectionStore: sourceConnectionStore
            )
            self.photosIndexService = photosIndexService
            self.filesImportService = filesImportService
            self.locationSnapshotService = locationSnapshotService
            let supportSettingsService = SupportSettingsAPIService.shared
            self.supportSettingsService = supportSettingsService
            let notesStoreService = NotesStoreService(memoryService: service)
            self.notesStoreService = notesStoreService
            let shareImportService = ShareImportService(notesStore: notesStoreService)
            self.shareImportService = shareImportService

            let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            if !isRunningTests {
                Task {
                    await supportSettingsService.syncSupportSettingsCache()
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
            Group {
                if onboardingComplete {
                    // Main app
                    NavigationStack {
                        ChatView(
                            pipeline: queryPipeline,
                            sourceConnectionStore: sourceConnectionStore,
                            photosIndexService: photosIndexService,
                            filesImportService: filesImportService,
                            locationSnapshotService: locationSnapshotService
                        )
                    }
                } else {
                    // Permission onboarding flow
                    NavigationStack {
                        PermissionOnboardingView(
                            pipeline: queryPipeline,
                            sourceConnectionStore: sourceConnectionStore,
                            photosIndexService: photosIndexService,
                            filesImportService: filesImportService,
                            locationSnapshotService: locationSnapshotService
                        )
                    }
                }
            }
            .environment(\.modelContext, modelContext)
        }
    }
}
