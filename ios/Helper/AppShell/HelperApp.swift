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
            let access = QuerySourceAccess()
            let interpreter = QueryInterpreter()
            let fetcher = QueryDataFetcher()
            let composer = QueryAnswerComposer()

            self.queryPipeline = QueryPipeline(
                interpreter: interpreter,
                access: access,
                fetcher: fetcher,
                composer: composer
            )

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
                    ChatView(pipeline: queryPipeline)
                } else {
                    // Permission onboarding flow
                    PermissionOnboardingView(pipeline: queryPipeline)
                }
            }
            .environment(\.modelContext, modelContext)
        }
    }
}
