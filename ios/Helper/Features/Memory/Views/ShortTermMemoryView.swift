import SwiftUI

struct ShortTermMemoryView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var settings = MemorySourceSettings()
    @StateObject private var coordinator = ShortTermMemoryCoordinator()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: IOS26Style.Spacing.sm) {
                if let emptyText = coordinator.emptyStateText {
                    EmptyMemoryCard(text: emptyText)
                        .ios26Card()
                } else {
                    MemoryOverviewCard(overview: coordinator.overview)
                        .ios26Card()

                    NextMemoryItemCard(items: coordinator.nextSixHours)
                        .ios26Card()

                    NextSixHoursCard(items: coordinator.nextSixHours)
                        .ios26Card()

                    WeekSummaryList(days: coordinator.daySummaries) { day in
                        WorkingMemoryDayView(date: day.date)
                            .environmentObject(settings)
                            .environmentObject(coordinator)
                    }
                }
            }
            .padding(.horizontal, IOS26Style.Spacing.md)
            .padding(.vertical, IOS26Style.Spacing.sm)
        }
        .ios26Page()
        .navigationTitle("Korttidsminne")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    MemorySourcesSettingsView()
                        .environmentObject(settings)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Öppna källor")
            }
        }
        .refreshable {
            await settings.refreshPermissionStatuses()
            await coordinator.refresh(using: settings)
        }
        .task {
            await settings.refreshPermissionStatuses()
            await coordinator.refresh(using: settings)
        }
        .onChange(of: settings.calendarEnabled) { _, _ in
            Task { await coordinator.refresh(using: settings) }
        }
        .onChange(of: settings.remindersEnabled) { _, _ in
            Task { await coordinator.refresh(using: settings) }
        }
        .onChange(of: settings.mailEnabled) { _, _ in
            Task { await coordinator.refresh(using: settings) }
        }
        .onChange(of: settings.healthEnabled) { _, _ in
            Task { await coordinator.refresh(using: settings) }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task {
                await settings.refreshPermissionStatuses()
                await coordinator.refresh(using: settings)
            }
        }
    }
}

private struct EmptyMemoryCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Inget att visa ännu", systemImage: "sparkles")
                .font(.headline)
                .symbolRenderingMode(.hierarchical)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MemoryOverviewCard: View {
    let overview: MemoryOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(overview.title)
                .font(.title2.weight(.semibold))

            Text(overview.line1)
                .font(.body)
                .foregroundStyle(.secondary)

            Text(overview.line2)
                .font(.body)
                .foregroundStyle(.secondary)

            if let updatedAt = overview.updatedAt {
                Label(
                    "Uppdaterad \(updatedAt.formatted(date: .omitted, time: .shortened))",
                    systemImage: "clock"
                )
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            }
        }
    }
}

private struct NextMemoryItemCard: View {
    let items: [MemoryTimelineItem]

    var body: some View {
        let nextItem = items.first

        VStack(alignment: .leading, spacing: 10) {
            Label("Närmaste", systemImage: "sparkle.magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let nextItem {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(nextItem.timeText)
                        .font(.title3.weight(.semibold))

                    Text(nextItem.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()
                }

                Text(kindLabel(nextItem.kind))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Inget inom närmaste 6 timmar.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func kindLabel(_ kind: MemoryTimelineKind) -> String {
        switch kind {
        case .calendar:
            return "Kalender"
        case .reminder:
            return "Påminnelse"
        }
    }
}

private struct NextSixHoursCard: View {
    let items: [MemoryTimelineItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Kommande 6 timmar", systemImage: "timeline.selection")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if items.isEmpty {
                        pill("Inget planerat")
                    } else {
                        ForEach(items) { item in
                            pill("\(item.timeText) \(item.title)")
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Capsule().fill(.thinMaterial))
            .overlay(
                Capsule()
                    .strokeBorder(.separator.opacity(0.55), lineWidth: 0.5)
            )
    }
}

private struct WeekSummaryList<Destination: View>: View {
    let days: [MemoryDaySummary]
    let destination: (MemoryDaySummary) -> Destination

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Kommande 7 dagar", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(days) { day in
                NavigationLink {
                    destination(day)
                } label: {
                    MemoryDayCard(day: day)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MemoryDayCard: View {
    let day: MemoryDaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dayLabel(day.date))
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Text("Nästa: \(day.nextText)")
                .font(.body)
                .lineLimit(1)

            ChipsRow(chips: day.chips)

            Text(day.bodyLine)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let updatedText = day.updatedText {
                Text(updatedText)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .ios26Card()
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date).capitalized
    }
}

private struct ChipsRow: View {
    let chips: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(chips.prefix(4), id: \.self) { chip in
                Text(chip)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Capsule().fill(.thinMaterial))
                    .overlay(
                        Capsule()
                            .strokeBorder(.separator.opacity(0.55), lineWidth: 0.5)
                    )
            }
        }
    }
}
