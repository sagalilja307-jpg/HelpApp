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

    // Onboarding flag (sparas i UserDefaults)
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    // MARK: - Init

    init() {
        do {
            // 1️⃣ Initiera MemoryService (root dependency)
            let service = try MemoryService()
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
            let backendQueryService = BackendQueryAPIService.shared

            self.queryPipeline = QueryPipeline(
                access: access,
                fetcher: fetcher,
                backendQueryService: backendQueryService,
                sourceConnectionStore: sourceConnectionStore
            )
            
            // 5️⃣ Other services
            self.photosIndexService = photosIndexService
            self.filesImportService = filesImportService
            self.locationSnapshotService = locationSnapshotService
            
            let supportSettingsService = SupportSettingsAPIService.shared
            self.supportSettingsService = supportSettingsService
            
            let notesStoreService = NotesStoreService()
            let shareImportService = ShareImportService(
                memoryService: service,
                notesStore: notesStoreService
            )
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

            NavigationStack {

                if onboardingComplete {

                    ChatView(
                        pipeline: queryPipeline,
                        sourceConnectionStore: sourceConnectionStore,
                        photosIndexService: photosIndexService,
                        filesImportService: filesImportService,
                        locationSnapshotService: locationSnapshotService
                    )

                } else {

                    PermissionsOnboardingFlow(onboardingComplete: $onboardingComplete)

                }
            }
            .environment(\.modelContext, modelContext)
        }
    }
}
