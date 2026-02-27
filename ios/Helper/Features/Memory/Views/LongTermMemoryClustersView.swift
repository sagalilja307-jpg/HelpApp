import SwiftUI

struct LongTermMemoryClustersView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator

    @State private var clusters: [LongTermMemoryCluster] = []
    @State private var isLoading = false

    init(longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator) {
        self.longTermMemorySaveCoordinator = longTermMemorySaveCoordinator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if clusters.isEmpty, !isLoading {
                    EmptyLongTermMemoryCard()
                        .ios26Card()
                } else {
                    ForEach(clusters) { cluster in
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
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .overlay(alignment: .center) {
            if isLoading {
                ProgressView()
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .background(IOS26Style.pageBackground)
        .navigationTitle("Långtidsminne")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityLabel("Uppdatera kluster")
            }
        }
        .task {
            await refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refresh() }
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

                Text("\(cluster.itemCount)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

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

            HStack(spacing: 8) {
                TagChip(text: typeText(cluster.dominantType), systemImage: "tag")
                ForEach(cluster.topTags.prefix(3), id: \.self) { tag in
                    TagChip(text: tag, systemImage: nil)
                }
            }
        }
    }

    private var clusterTitle: String {
        if let firstTag = cluster.topTags.first {
            return firstTag.capitalized
        }
        return typeText(cluster.dominantType)
    }

    private func typeText(_ type: LongTermMemoryType) -> String {
        switch type {
        case .insight: return "Insight"
        case .idea: return "Idea"
        case .decision: return "Decision"
        case .question: return "Question"
        case .risk: return "Risk"
        case .other: return "Other"
        }
    }
}

private struct TagChip: View {
    let text: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Capsule().fill(.thinMaterial))
        .overlay(
            Capsule()
                .strokeBorder(.separator.opacity(0.55), lineWidth: 0.5)
        )
    }
}

private struct LongTermMemoryClusterDetailView: View {
    let cluster: LongTermMemoryCluster
    let longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator

    @State private var items: [LongTermMemoryItem] = []

    var body: some View {
        List {
            if items.isEmpty {
                Text("Inga minnen i detta kluster ännu.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.cleanText)
                            .font(.body)
                            .lineLimit(3)

                        HStack(spacing: 8) {
                            Text(item.suggestedType)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(clusterTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            items = longTermMemorySaveCoordinator.loadItems(for: cluster)
        }
    }

    private var clusterTitle: String {
        if let firstTag = cluster.topTags.first, !firstTag.isEmpty {
            return firstTag.capitalized
        }
        return "Kluster"
    }
}
