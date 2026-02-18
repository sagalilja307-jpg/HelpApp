//
//  PermissionOnboardingView.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-30.
//


import SwiftUI

struct PermissionOnboardingView: View {

    let type: AppPermissionType

    @State private var status: AppPermissionStatus = .notDetermined
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {

            Spacer(minLength: 28)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 72, height: 72)

                    Image(systemName: iconName)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            Spacer(minLength: 24)

            VStack(spacing: 14) {

                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)

                    Text("Det här är valfritt – du kan ändra senare i Inställningar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Divider()
                    .opacity(0.7)
                    .padding(.horizontal, 16)

                actionArea
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .padding(.horizontal, 20)

            Spacer(minLength: 16)
        }
        .padding(.top, 8)
        .task {
            status = await PermissionManager.shared.status(for: type)
        }
        .animation(.easeInOut(duration: 0.2), value: status)
    }

    @ViewBuilder
    private var actionArea: some View {
        switch status {
        case .granted:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                Text("Beviljad")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)

        case .denied:
            Button {
                openSettings()
            } label: {
                Text("Öppna Inställningar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

        case .notDetermined:
            Button {
                request()
            } label: {
                HStack(spacing: 10) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Text(isLoading ? "Begär åtkomst…" : "Ge tillgång")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
    }

    private func request() {
        isLoading = true
        Task {
            try? await PermissionManager.shared.requestAccess(for: type)
            status = await PermissionManager.shared.status(for: type)
            isLoading = false
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var title: String {
        switch type {
        case .calendar: return "Tillåt Kalender"
        case .reminder: return "Tillåt Påminnelser"
        case .notification: return "Tillåt Notiser"
        case .camera: return "Tillåt Kamera"
        case .contacts: return "Tillåt Kontakter"
        case .photos: return "Tillåt Bilder"
        case .location: return "Tillåt Plats"
        }
    }

    private var description: String {
        switch type {
        case .notification: return "Få viktiga uppdateringar och påminnelser."
        case .photos: return "Välj bilder för att dela eller spara innehåll."
        case .camera: return "Ta bilder direkt i appen när du behöver det."
        case .contacts: return "Hitta och bjuda in personer snabbare."
        case .location: return "Används för bättre resultat nära dig."
        case .calendar: return "Synka händelser så att allt finns samlat."
        case .reminder: return "Skapa och hantera påminnelser i appen."
        }
    }

    private var iconName: String {
        switch type {
        case .calendar: return "calendar"
        case .reminder: return "checklist"
        case .notification: return "bell"
        case .camera: return "camera"
        case .contacts: return "person.crop.circle"
        case .photos: return "photo.on.rectangle"
        case .location: return "location"
        }
    }
}
