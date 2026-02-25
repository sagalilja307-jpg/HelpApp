import SwiftUI

struct DataSourcesSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var settingsStore: DataSettingsStore

    init(
        sourceConnectionStore: SourceConnectionStore,
        photosIndexService _: PhotosIndexService,
        filesImportService _: FilesImportService,
        locationSnapshotService _: LocationSnapshotService? = nil
    ) {
        _settingsStore = StateObject(
            wrappedValue: DataSettingsStore(sourceConnectionStore: sourceConnectionStore)
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DomainCatalog.all) { domain in
                        NavigationLink {
                            DataDomainView(domain: domain)
                                .environmentObject(settingsStore)
                        } label: {
                            DataDomainRow(
                                domain: domain,
                                isEnabled: settingsStore.isDomainEnabled(domain.id),
                                enabledSources: enabledSourceCount(in: domain),
                                supportedSources: supportedSourceCount(in: domain)
                            )
                        }
                    }
                } header: {
                    Text("Domäner")
                } footer: {
                    Text("Källor som ännu inte stöds visas som oaktiverade.")
                }
            }
            .navigationTitle("Datakällor")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Klar") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await settingsStore.refreshPermissionStatuses()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await settingsStore.refreshPermissionStatuses() }
        }
    }

    private func enabledSourceCount(in domain: DataDomain) -> Int {
        domain.sources.filter { source in
            settingsStore.isSourceSupported(source.id)
                && settingsStore.isSourceEnabled(source.id)
        }.count
    }

    private func supportedSourceCount(in domain: DataDomain) -> Int {
        domain.sources.filter { source in
            settingsStore.isSourceSupported(source.id)
        }.count
    }
}

private struct DataDomainRow: View {
    let domain: DataDomain
    let isEnabled: Bool
    let enabledSources: Int
    let supportedSources: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(domain.title)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(isEnabled ? "På" : "Av")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
            }

            Text(domain.description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if supportedSources > 0 {
                Text("\(enabledSources)/\(supportedSources) aktiverade")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Inga tillgängliga källor i denna version")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
