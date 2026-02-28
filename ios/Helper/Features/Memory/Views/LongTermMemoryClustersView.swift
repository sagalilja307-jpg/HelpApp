import SwiftUI

struct LongTermMemoryClustersView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator

    @State private var clusters: [LongTermMemoryCluster] = []
    @State private var isLoading = false
    @State private var searchText = ""

    init(longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator) {
        self.longTermMemorySaveCoordinator = longTermMemorySaveCoordinator
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: IOS26Style.Spacing.sm) {
                if filteredClusters.isEmpty, !isLoading {
                    if searchText.isEmpty {
                        EmptyLongTermMemoryCard()
                            .ios26Card()
                    } else {
                        ContentUnavailableView(
                            "Inga träffar",
                            systemImage: "magnifyingglass",
                            description: Text("Prova ett annat sökord.")
                        )
                        .ios26Card()
                    }
                } else {
                    ForEach(filteredClusters) { cluster in
                        NavigationLink {
                            LongTermMemoryClusterDetailView(
                                cluster: cluster,
                                longTermMemorySaveCoordinator: longTermMemorySaveCoordinator
                            )
                        } label: {
                            LongTermMemoryClusterCard(cluster: cluster)
                                .ios26Card()
                        }
                        .buttonStyle(.plain)
                        .ios26Pressable()
                    }
                }
            }
            .padding(.horizontal, IOS26Style.Spacing.md)
            .padding(.vertical, IOS26Style.Spacing.sm)
        }
        .overlay(alignment: .center) {
            if isLoading {
                ProgressView()
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.separator.opacity(0.55), lineWidth: IOS26Style.Metrics.strokeWidth)
                    )
            }
        }
        .ios26Page()
        .navigationTitle("Långtidsminne")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Sök kluster")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(isLoading)
                .accessibilityLabel("Uppdatera kluster")
            }
        }
        .refreshable {
            await refresh()
        }
        .task {
            await refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refresh() }
        }
        .animation(.snappy, value: filteredClusters.count)
    }

    private var filteredClusters: [LongTermMemoryCluster] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return clusters
        }
        let q = searchText.lowercased()
        return clusters.filter { cluster in
            let title = (cluster.topTags.first ?? cluster.dominantType.displayName).lowercased()
            let tags = cluster.topTags.joined(separator: " ").lowercased()
            let sample = (cluster.sampleText ?? "").lowercased()
            return title.contains(q) || tags.contains(q) || sample.contains(q)
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        clusters = longTermMemorySaveCoordinator.loadClusters()
    }
}

private struct EmptyLongTermMemoryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Inga kluster ännu", systemImage: "square.grid.2x2")
                .font(.headline)
                .symbolRenderingMode(.hierarchical)

            Text("Spara fler minnen i chatten för att bygga temagrupper.")
                .font(.body)
                .foregroundStyle(.secondary)

            IOS26Style.badge("Tips: spara viktiga svar", systemImage: "sparkles", prominence: .secondary)
        }
    }
}

private struct LongTermMemoryClusterCard: View {
    let cluster: LongTermMemoryCluster

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(clusterTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                IOS26Style.badge("\(cluster.itemCount)", prominence: .secondary)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            if let sampleText = cluster.sampleText, !sampleText.isEmpty {
                Text(sampleText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            FlowChips {
                IOS26Style.badge(cluster.dominantType.displayName, systemImage: "tag", prominence: .secondary)
                ForEach(cluster.topTags.prefix(3), id: \.self) { tag in
                    IOS26Style.badge(tag, prominence: .secondary)
                }
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(clusterTitle), \(cluster.itemCount) minnen")
    }

    private var clusterTitle: String {
        if let firstTag = cluster.topTags.first {
            return firstTag.capitalized
        }
        return cluster.dominantType.displayName
    }
}

/// A tiny flow layout for chips that wraps on small screens.
private struct FlowChips<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        // Works well enough for MVP: let it wrap by using an adaptive grid.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
            content()
        }
    }
}

private struct LongTermMemoryClusterDetailView: View {
    let cluster: LongTermMemoryCluster
    let longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator

    @State private var items: [LongTermMemoryItem] = []
    @State private var searchText = ""

    var body: some View {
        List {
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Inga minnen i detta kluster ännu." : "Inga träffar",
                    systemImage: searchText.isEmpty ? "tray" : "magnifyingglass"
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(filteredItems, id: \.id) { item in
                    NavigationLink {
                        LongTermMemoryItemDetailView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.cleanText)
                                .font(.body)
                                .lineLimit(3)

                            FlowChips {
                                IOS26Style.badge(item.normalizedType.displayName, systemImage: "brain.head.profile", prominence: .secondary)
                                IOS26Style.badge(item.normalizedDomain.displayName, systemImage: "square.grid.2x2", prominence: .secondary)
                                IOS26Style.badge(item.normalizedActionState.displayName, systemImage: "checklist", prominence: .secondary)
                                IOS26Style.badge(item.normalizedTimeRelation.displayName, systemImage: "calendar", prominence: .secondary)
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(clusterTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Sök i klustret")
        .task {
            items = longTermMemorySaveCoordinator.loadItems(for: cluster)
        }
    }

    private var filteredItems: [LongTermMemoryItem] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return items }
        let q = searchText.lowercased()
        return items.filter {
            $0.cleanText.lowercased().contains(q) ||
            $0.cognitiveType.lowercased().contains(q) ||
            $0.domain.lowercased().contains(q) ||
            $0.actionState.lowercased().contains(q) ||
            $0.timeRelation.lowercased().contains(q)
        }
    }

    private var clusterTitle: String {
        if let firstTag = cluster.topTags.first, !firstTag.isEmpty {
            return firstTag.capitalized
        }
        return "Kluster"
    }
}
