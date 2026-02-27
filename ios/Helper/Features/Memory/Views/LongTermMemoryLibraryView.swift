import SwiftUI

struct LongTermMemoryLibraryView: View {
    private let longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator

    init(longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator) {
        self.longTermMemorySaveCoordinator = longTermMemorySaveCoordinator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NavigationLink {
                    LongTermMemoryTimelineView(
                        longTermMemorySaveCoordinator: longTermMemorySaveCoordinator
                    )
                } label: {
                    LongTermMemoryRouteCard(
                        title: "1. Tidslinje",
                        subtitle: "Se alla minnen i kronologisk ordning.",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .ios26Card()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Öppna långtidsminnets tidslinje")

                NavigationLink {
                    LongTermMemoryClustersView(
                        longTermMemorySaveCoordinator: longTermMemorySaveCoordinator
                    )
                } label: {
                    LongTermMemoryRouteCard(
                        title: "2. Kluster",
                        subtitle: "Utforska minnen grupperade efter likhet.",
                        systemImage: "square.grid.2x2"
                    )
                    .ios26Card()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Öppna långtidsminnets kluster")

                NavigationLink {
                    LongTermMemoryTypesView(
                        longTermMemorySaveCoordinator: longTermMemorySaveCoordinator
                    )
                } label: {
                    LongTermMemoryRouteCard(
                        title: "3. Typer",
                        subtitle: "Bläddra minnen per typ och frekvens.",
                        systemImage: "tag"
                    )
                    .ios26Card()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Öppna långtidsminnets typer")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(IOS26Style.pageBackground)
        .navigationTitle("Långtidsminne")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct LongTermMemoryRouteCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

struct LongTermMemoryTimelineView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator

    @State private var items: [LongTermMemoryItem] = []
    @State private var isLoading = false

    init(longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator) {
        self.longTermMemorySaveCoordinator = longTermMemorySaveCoordinator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if items.isEmpty, !isLoading {
                    LongTermMemoryEmptyCard(
                        title: "Inga minnen ännu",
                        text: "Spara innehåll från chatten så dyker det upp här."
                    )
                    .ios26Card()
                } else {
                    ForEach(items, id: \.id) { item in
                        NavigationLink {
                            LongTermMemoryItemDetailView(item: item)
                        } label: {
                            LongTermMemoryTimelineItemCard(item: item)
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
        .navigationTitle("Långtidsminne · Tidslinje")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityLabel("Uppdatera tidslinje")
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
        items = longTermMemorySaveCoordinator.loadAllItems()
    }
}

private struct LongTermMemoryTimelineItemCard: View {
    let item: LongTermMemoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                LongTermMemoryTagChip(text: item.normalizedType.displayName, systemImage: "tag")

                Spacer()

                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(item.cleanText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(3)

            if !item.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(item.tags.prefix(4), id: \.self) { tag in
                            LongTermMemoryTagChip(text: tag, systemImage: nil)
                        }
                    }
                }
            }
        }
    }
}

struct LongTermMemoryTypesView: View {
    @Environment(\.scenePhase) private var scenePhase

    private let longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator

    @State private var sections: [LongTermMemoryTypeSection] = []
    @State private var isLoading = false

    init(longTermMemorySaveCoordinator: LongTermMemorySaveCoordinator) {
        self.longTermMemorySaveCoordinator = longTermMemorySaveCoordinator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if sections.isEmpty, !isLoading {
                    LongTermMemoryEmptyCard(
                        title: "Inga typer ännu",
                        text: "När minnen sparas grupperas de automatiskt per typ."
                    )
                    .ios26Card()
                } else {
                    ForEach(sections) { section in
                        NavigationLink {
                            LongTermMemoryTypeDetailView(section: section)
                        } label: {
                            LongTermMemoryTypeSectionCard(section: section)
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
        .navigationTitle("Långtidsminne · Typer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityLabel("Uppdatera typer")
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

        let items = longTermMemorySaveCoordinator.loadAllItems()
        sections = LongTermMemoryType.allCases.compactMap { type in
            let grouped = items.filter { $0.normalizedType == type }
            guard !grouped.isEmpty else { return nil }
            return LongTermMemoryTypeSection(type: type, items: grouped)
        }
    }
}

private struct LongTermMemoryTypeSection: Identifiable {
    let type: LongTermMemoryType
    let items: [LongTermMemoryItem]

    var id: String { type.rawValue }
    var count: Int { items.count }
}

private struct LongTermMemoryTypeSectionCard: View {
    let section: LongTermMemoryTypeSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.type.displayName)
                    .font(.headline)

                Spacer()

                Text("\(section.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            if let latest = section.items.first {
                Text(latest.cleanText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct LongTermMemoryTypeDetailView: View {
    let section: LongTermMemoryTypeSection

    var body: some View {
        List {
            ForEach(section.items, id: \.id) { item in
                NavigationLink {
                    LongTermMemoryItemDetailView(item: item)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.cleanText)
                            .font(.body)
                            .lineLimit(3)

                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(section.type.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LongTermMemoryItemDetailView: View {
    let item: LongTermMemoryItem

    var body: some View {
        List {
            Section {
                HStack {
                    LongTermMemoryTagChip(text: item.normalizedType.displayName, systemImage: "tag")
                    Spacer()
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Section("Strukturerad text") {
                Text(item.cleanText)
                    .textSelection(.enabled)
            }

            if item.originalText != item.cleanText {
                Section("Originaltext") {
                    Text(item.originalText)
                        .textSelection(.enabled)
                }
            }

            if !item.tags.isEmpty {
                Section("Taggar") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(item.tags, id: \.self) { tag in
                                LongTermMemoryTagChip(text: tag, systemImage: nil)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Minne")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LongTermMemoryEmptyCard: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "tray")
                .font(.headline)
                .symbolRenderingMode(.hierarchical)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LongTermMemoryTagChip: View {
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
