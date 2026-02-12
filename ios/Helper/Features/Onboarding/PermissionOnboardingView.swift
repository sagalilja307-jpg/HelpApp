//
//  PermissionOnboardingView.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-30.
//


import SwiftUI

struct PermissionOnboardingView: View {
    let pipeline: QueryPipeline

    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var currentIndex: Int? = nil
    @State private var isChecking = true

    private let steps: [AppPermissionType] = [
        .calendar,
        .reminder,
        .notification,
        .camera
    ]

    var body: some View {
        Group {
            if isChecking {
                ProgressView("Kontrollerar tillgångar...")
                    .task { await checkNextPermission(startIndex: 0) }
            } else if let index = currentIndex, index < steps.count {
                VStack(spacing: 32) {
                    PermissionView(type: steps[index])

                    Button("Nästa") {
                        Task {
                            await checkNextPermission(startIndex: index + 1)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }
                .transition(.slide)
                .padding()
            } else {
                ChatView(pipeline: pipeline)
            }
        }
        .animation(.easeInOut, value: currentIndex)
    }

    private func checkNextPermission(startIndex: Int) async {
        for i in startIndex..<steps.count {
            let type = steps[i]
            let status = await PermissionManager.shared.status(for: type)
            if status != .granted {
                await MainActor.run {
                    currentIndex = i
                    isChecking = false
                }
                return
            }
        }

        // Alla permissions är klara
        await MainActor.run {
            onboardingComplete = true
        }
    }
}
