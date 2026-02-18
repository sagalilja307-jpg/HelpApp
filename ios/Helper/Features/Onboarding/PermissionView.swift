import SwiftUI
import UIKit

struct PermissionSimpleView: View {

    let type: AppPermissionType
    let onContinue: () -> Void

    @State private var status: AppPermissionStatus = .notDetermined
    @State private var isLoading = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 24) {

            Text(title)
                .font(.title2)
                .bold()

            Text(description)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            switch status {

            case .granted:
                Button("Fortsätt") { onContinue() }
                    .buttonStyle(.borderedProminent)

            case .denied:
                Button("Öppna Inställningar") { openSettings() }
                    .buttonStyle(.bordered)

            case .notDetermined:
                Button { request() } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Ge tillgång")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }
        }
        .task {
            status = await PermissionManager.shared.status(for: type)
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task {
                status = await PermissionManager.shared.status(for: type)
            }
        }
    }

    private func request() {
        isLoading = true

        Task {
            defer { isLoading = false }
            try? await PermissionManager.shared.requestAccess(for: type)
            status = await PermissionManager.shared.status(for: type)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var title: String {
        switch type {
        case .calendar: return "Kalender"
        case .reminder: return "Påminnelser"
        case .notification: return "Notiser"
        case .camera: return "Kamera"
        case .contacts: return "Kontakter"
        case .photos: return "Bilder"
        case .location: return "Plats"
        }
    }

    private var description: String {
        "Appen behöver denna tillgång för att fungera korrekt."
    }
}


