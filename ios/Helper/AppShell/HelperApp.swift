//
//  HelperApp.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-24.
//

import SwiftData
import SwiftUI

@main
struct HelperApp: App {
    private let runtime: HelperAppRuntime

    @AppStorage("helper.onboarding.done") private var onboardingDone = false

    init() {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        do {
            let runtime = try HelperAppBootstrap.build(isRunningTests: isRunningTests)
            self.runtime = runtime

            if !isRunningTests {
                runtime.startBackgroundServices()
            }
        } catch {
            fatalError("Failed to initialize HelperApp core services: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if onboardingDone {
                    ChatView(
                        pipeline: runtime.queryPipeline,
                        sourceConnectionStore: runtime.sourceConnectionStore,
                        photosIndexService: runtime.photosIndexService,
                        filesImportService: runtime.filesImportService,
                        locationSnapshotService: runtime.locationSnapshotService,
                        longTermMemorySaveCoordinator: runtime.longTermMemorySaveCoordinator,
                        iCloudSyncCoordinator: runtime.iCloudSyncCoordinator,
                        iCloudMemorySyncCoordinator: runtime.iCloudMemorySyncCoordinator
                    )
                } else {
                    OnboardingView(onboardingComplete: $onboardingDone)
                }
            }
            .environment(\.modelContext, runtime.modelContext)
        }
    }
}
