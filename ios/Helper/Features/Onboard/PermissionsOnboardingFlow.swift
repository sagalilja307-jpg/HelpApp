//
//  PermissionsOnboardingFlow.swift
//  Helper
//
//  Created by Saga Lilja on 2026-02-18.
//


import SwiftUI

struct PermissionsOnboardingFlow: View {

    @Binding var onboardingComplete: Bool

    private let steps: [AppPermissionType]

    @State private var index: Int = 0
    @State private var isAdvancing = false

    init(onboardingComplete: Binding<Bool>,
         steps: [AppPermissionType] = [
            .photos,
            .notification,
            .camera,
            .contacts,
            .location,
            .calendar,
            .reminder
         ]) {
        self._onboardingComplete = onboardingComplete
        self.steps = steps
    }

    var body: some View {
        VStack(spacing: 0) {

            header

            ZStack {
                PermissionOnboardingView(
                    type: currentType,
                    isLastStep: isLastStep,
                    onContinue: { goNext() }
                )
                    .id(currentType)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.25), value: index)
        }
        .padding(.top, 8)
        .task {
            await moveToNextPendingPermission(from: 0)
        }
    }

    // MARK: - UI

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button("Hoppa över") { finish() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            ProgressView(value: Double(index + 1), total: Double(steps.count))
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }

    private var currentType: AppPermissionType {
        steps[min(max(index, 0), steps.count - 1)]
    }

    private var isLastStep: Bool {
        index >= steps.count - 1
    }

    private func goNext() {
        Task {
            await moveToNextPendingPermission(from: index + 1)
        }
    }

    @MainActor
    private func moveToNextPendingPermission(from startIndex: Int) async {
        guard !isAdvancing else { return }
        isAdvancing = true
        defer { isAdvancing = false }

        var nextIndex = max(startIndex, 0)
        while nextIndex < steps.count {
            let status = await PermissionManager.shared.status(for: steps[nextIndex])
            if status == .granted {
                nextIndex += 1
                continue
            }
            index = nextIndex
            return
        }

        finish()
    }

    private func finish() {
        onboardingComplete = true
    }
}
