import SwiftUI
import MapKit
import CoreLocation

// MARK: - Data Models

struct SummaryCardData: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let caption: String?
    let icon: String

    init(
        title: String,
        value: String,
        caption: String? = nil,
        icon: String = "square.grid.2x2"
    ) {
        self.title = title
        self.value = value
        self.caption = caption
        self.icon = icon
    }
}

struct TimelineItem: Identifiable {
    let id = UUID()
    let title: String
    let date: String
    let subtitle: String?
    let source: String?

    init(
        title: String,
        date: String,
        subtitle: String? = nil,
        source: String? = nil
    ) {
        self.title = title
        self.date = date
        self.subtitle = subtitle
        self.source = source
    }
}

struct GroupedItem: Identifiable {
    let id = UUID()
    let title: String
    let group: String
    let subtitle: String?

    init(title: String, group: String, subtitle: String? = nil) {
        self.title = title
        self.group = group
        self.subtitle = subtitle
    }
}

struct FlowItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String?

    init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }
}

// MARK: - Shared Style

private struct VisualizationCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.separator.opacity(0.45), lineWidth: 0.6)
                    )
            )
    }
}

private extension View {
    func vizCard() -> some View {
        modifier(VisualizationCardModifier())
    }
}

// MARK: - 1) SummaryCards

struct SummaryCardsView: View {
    let items: [SummaryCardData]

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(item.value)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    if let caption = item.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                .vizCard()
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }
}

// MARK: - 2) Narrative

struct NarrativeView: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "text.justify")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
        .vizCard()
        .padding(.horizontal, 2)
    }
}

// MARK: - 3) Focus

struct FocusView: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Senaste fokus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .lineLimit(2)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vizCard()
        .padding(.horizontal, 2)
    }
}

// MARK: - 4) Timeline

struct TimelineView: View {
    let items: [TimelineItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tidslinje", systemImage: "timeline.selection")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(items.prefix(8)) { item in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.2))
                            .frame(width: 2, height: 40)
                    }
                    .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            Text(item.date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        if let source = item.source, !source.isEmpty {
                            Text(source)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .vizCard()
        .padding(.horizontal, 2)
    }
}

// MARK: - 5) WeekScroll

struct WeekScrollView: View {
    let days: [String]
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Dagöversikt", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        Button {
                            selected = day
                        } label: {
                            Text(day)
                                .font(.footnote.weight(.semibold))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(
                                    Capsule()
                                        .fill(selected == day ? Color.accentColor : Color(.systemGray6))
                                )
                                .foregroundStyle(selected == day ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .vizCard()
        .padding(.horizontal, 2)
        .onAppear {
            if selected == nil {
                selected = days.first
            }
        }
    }
}

// MARK: - 6) GroupedList

struct GroupedListView: View {
    let items: [GroupedItem]

    private var grouped: [(key: String, values: [GroupedItem])] {
        Dictionary(grouping: items, by: { $0.group })
            .map { ($0.key, $0.value) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Grupperad vy", systemImage: "square.grid.3x3.topleft.filled")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(grouped, id: \.key) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.key)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(section.values.prefix(6)) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            if let subtitle = item.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.thinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(.separator.opacity(0.45), lineWidth: 0.5)
                                )
                        )
                    }
                }
            }
        }
        .vizCard()
        .padding(.horizontal, 2)
    }
}

// MARK: - 7) Map

struct SimpleMapView: View {
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Plats", systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Map(
                initialPosition: .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                    )
                )
            )
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .vizCard()
        .padding(.horizontal, 2)
    }
}

// MARK: - 8) Flow

struct FlowView: View {
    let steps: [FlowItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Flöde", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.prefix(5).enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.2))
                                .frame(width: 26, height: 26)
                            Text("\(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.subheadline.weight(.semibold))

                            if let detail = step.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()
                    }
                }
            }
        }
        .vizCard()
        .padding(.horizontal, 2)
    }
}

// MARK: - 9) Heatmap

struct HeatmapView: View {
    let values: [[Double]]

    private let dayLabels = ["M", "T", "O", "T", "F", "L", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Aktivitetsmönster", systemImage: "square.grid.4x3.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(values.indices, id: \.self) { row in
                    HStack(spacing: 6) {
                        Text(dayLabel(for: row))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, alignment: .leading)

                        ForEach(values[row].indices, id: \.self) { col in
                            let intensity = max(0.06, min(1.0, values[row][col]))
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.accentColor.opacity(intensity))
                                .frame(width: 24, height: 24)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Text("Natt")
                Spacer()
                Text("Morgon")
                Spacer()
                Text("Eftermiddag")
                Spacer()
                Text("Kväll")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .vizCard()
        .padding(.horizontal, 2)
    }

    private func dayLabel(for index: Int) -> String {
        guard dayLabels.indices.contains(index) else { return "-" }
        return dayLabels[index]
    }
}
