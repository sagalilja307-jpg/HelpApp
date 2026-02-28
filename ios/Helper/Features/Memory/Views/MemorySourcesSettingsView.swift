import SwiftUI
import UIKit

struct MemorySourcesSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: MemorySourceSettings

    var body: some View {
        Form {
            Section {
                Text("Välj vilka källor som får bidra till korttidsminnet. Du kan stänga av en källa här utan att ta bort behörighet i systemet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Källor för korttidsminne") {
                ForEach(MemorySourceID.allCases) { source in
                    MemorySourceToggleRow(source: source)
                        .environmentObject(settings)
                }
            }

            if settings.hasDeniedEnabledSources {
                Section {
                    Button {
                        openAppSettings()
                    } label: {
                        Label("Öppna Inställningar", systemImage: "gear")
                    }
                } footer: {
                    Text("En eller flera källor är nekade i systemet. Tillåt åtkomst i Inställningar för att synkningen ska fungera.")
                }
            }

            Section {
                Text("Korttidsminnet följer dina aktiva datakällor. Om Mail eller Hälsa är på i Datakällor kan de även aktiveras här.")
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

    private var isSupported: Bool { settings.isSupported(source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(source.title, systemImage: source.iconName)

                Spacer(minLength: 10)

                let permissionLabel = settings.permissionState(for: source).label
                let isGranted = settings.permissionState(for: source) == .granted

                IOS26Style.badge(
                    permissionLabel,
                    systemImage: isGranted ? "checkmark.circle" : "exclamationmark.triangle",
                    prominence: isGranted ? .secondary : .primary
                )

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

            if !isSupported {
                Text("Den här källan stöds inte på den här enheten just nu.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if source == .mail, settings.permissionState(for: .mail) != .granted {
                Text("Anslut Gmail i Datakällor för att aktivera mail här.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
