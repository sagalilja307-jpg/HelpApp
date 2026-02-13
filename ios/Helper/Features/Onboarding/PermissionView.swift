import SwiftUI

struct PermissionView: View {

    let type: AppPermissionType
    var onGranted: (() -> Void)? = nil

    @State private var status: AppPermissionStatus = .notDetermined
    @State private var isRequesting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            // Ikon
            Image(systemName: iconName)
                .font(.system(size: 48, weight: .semibold))

            // Titel
            Text(title)
                .font(.title)
                .bold()

            // Beskrivning
            Text(description)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            // Felmeddelande (om det finns)
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            // Åtgärder beroende på status
            switch status {
            case .granted:
                Label("Tillgång beviljad", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)

            case .denied:
                Button("Öppna Inställningar") {
                    openSettings()
                }

            case .notDetermined:
                Button(action: requestPermission) {
                    if isRequesting {
                        ProgressView()
                    } else {
                        Text("Ge tillgång")
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequesting)
            }
        }
        .padding(24)
        .task {
            await refreshStatus()
        }
    }

    // MARK: - Dynamiska texter & ikoner

    private var iconName: String {
        switch type {
        case .calendar: return "calendar.badge.exclamationmark"
        case .reminder: return "checklist"
        case .notification: return "bell.badge"
        case .camera: return "camera.viewfinder"
        case .contacts: return "person.2.fill"
        case .photos: return "photo.on.rectangle.angled"
        }
    }

    private var title: String {
        switch type {
        case .calendar: return "Tillgång till kalender"
        case .reminder: return "Tillgång till påminnelser"
        case .notification: return "Tillåt notiser"
        case .camera: return "Tillgång till kamera"
        case .contacts: return "Tillgång till kontakter"
        case .photos: return "Tillgång till bilder"
        }
    }

    private var description: String {
        switch type {
        case .calendar:
            return "För att kunna lägga in förslag direkt i din kalender behöver appen tillgång."
        case .reminder:
            return "För att kunna skapa påminnelser åt dig behöver appen tillgång."
        case .notification:
            return "Notiser används för att ställa frågor och ge förslag när det passar."
        case .camera:
            return "Kameran används för att scanna dokument och bilder."
        case .contacts:
            return "Kontakter används när du vill låta hjälparen svara med kontaktkontext."
        case .photos:
            return "Bilder används när du aktiverar bildindexering i datakällor."
        }
    }

    // MARK: - Behörighetsbegäran

    // MARK: - Statusuppdatering
    private func refreshStatus() async {
        // If PermissionManager.status(for:) is async, this await compiles.
        // If it's sync, consider adding an async overload or adjust here accordingly.
        // We use Task.yield() to ensure this runs cooperatively on the main actor.
        await Task.yield()
        self.status = await PermissionManager.shared.status(for: type)
    }

    private func requestPermission() {
        isRequesting = true
        errorMessage = nil

        Task {
            do {
                switch type {
                case .calendar:
                    try await PermissionManager.shared.requestCalendarAccess()
                case .reminder:
                    try await PermissionManager.shared.requestReminderAccess()
                case .notification:
                    try await PermissionManager.shared.requestNotificationAccess()
                case .camera:
                    try await PermissionManager.shared.requestCameraAccess()
                case .contacts:
                    try await PermissionManager.shared.requestContactsAccess()
                case .photos:
                    try await PermissionManager.shared.requestPhotosAccess()
                }

                status = .granted
                onGranted?()

            } catch {
                errorMessage = error.localizedDescription
            }

            isRequesting = false
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
