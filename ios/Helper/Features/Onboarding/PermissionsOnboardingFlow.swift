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

    init(onboardingComplete: Binding<Bool>,
         steps: [AppPermissionType] = [
            .notification,
            .photos,
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
                PermissionOnboardingView(type: currentType)
                    .id(currentType)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.25), value: index)


            // “Alltid möjlig att gå vidare”
            footer
        }
        .padding(.top, 8)
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

    private var footer: some View {
        VStack(spacing: 10) {
            Text("Steg \(index + 1) av \(steps.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Inte nu") {
                    goNext()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button(index == steps.count - 1 ? "Börja" : "Fortsätt") {
                    goNext()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Logic

    private var currentType: AppPermissionType {
        steps[min(max(index, 0), steps.count - 1)]
    }

    private func goNext() {
        if index < steps.count - 1 {
            index += 1
        } else {
            finish()
        }
    }

    private func finish() {
        onboardingComplete = true
    }
}
