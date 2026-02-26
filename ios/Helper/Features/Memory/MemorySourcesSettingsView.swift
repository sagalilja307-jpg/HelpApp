import SwiftUI
import UIKit

struct MemorySourcesSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: MemorySourceSettings

    var body: some View {
        Form {
            Section("Källor för korttidsminne") {
                ForEach(MemorySourceID.allCases) { source in
                    MemorySourceToggleRow(source: source)
                        .environmentObject(settings)
                }
            }

            if settings.hasDeniedEnabledSources {
                Section {
                    Button("Öppna Inställningar") {
                        openAppSettings()
                    }
                } footer: {
                    Text("En eller flera källor är nekade i systemet. Tillåt åtkomst i Inställningar för att synkning ska fungera.")
                }
            }

            Section {
                Text("Korttidsminnet visar bara de källor du själv valt. Hälsa är inte aktiverat ännu och visas därför som oaktiverad.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Källor")
        .navigationBarTitleDisplayMode(.inline)
        .symbolRenderingMode(.hierarchical)
        .task {
            await settings.refreshPermissionStatuses()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await settings.refreshPermissionStatuses() }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct MemorySourceToggleRow: View {
    let source: MemorySourceID

    @EnvironmentObject private var settings: MemorySourceSettings

    private var isSupported: Bool {
        settings.isSupported(source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(source.title, systemImage: source.iconName)

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { settings.isEnabled(source) },
                        set: { newValue in
                            Task {
                                _ = await settings.setSource(source, enabled: newValue)
                            }
                        }
                    )
                )
                .labelsHidden()
                .disabled(!isSupported)
                .opacity(isSupported ? 1 : 0.45)
            }

            Text(source.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Status: \(settings.permissionState(for: source).label)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if source == .mail, settings.permissionState(for: .mail) != .granted {
                Text("Logga in på Gmail i chatten för att aktivera mail här.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
