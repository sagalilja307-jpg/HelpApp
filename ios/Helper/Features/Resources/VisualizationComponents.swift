import SwiftUI
import MapKit
import CoreLocation

// MARK: - Data Models

struct SummaryCardData: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

struct TimelineItem: Identifiable {
    let id = UUID()
    let title: String
    let date: String
}

struct GroupedItem: Identifiable {
    let id = UUID()
    let title: String
    let group: String
}

struct FlowItem: Identifiable {
    let id = UUID()
    let title: String
}

// MARK: - 1️⃣ SummaryCards

struct SummaryCardsView: View {
    let items: [SummaryCardData]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 16
        ) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 12) {
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(item.value)
                        .font(.system(size: 28, weight: .bold))

                    Spacer()
                }
                .padding()
                .frame(height: 110)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
            }
        }
        .padding()
    }
}

// MARK: - 2️⃣ Narrative

struct NarrativeView: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .bold()

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(6)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding()
    }
}

// MARK: - 3️⃣ Focus

struct FocusView: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Focus")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(value)
                .font(.largeTitle)
                .bold()
                .foregroundStyle(accent)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.15), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding()
    }
}

// MARK: - 4️⃣ Timeline

struct TimelineView: View {
    let items: [TimelineItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 16) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - 5️⃣ WeekScroll

struct WeekScrollView: View {
    let days: [String]
    @State private var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(days, id: \.self) { day in
                    Text(day)
                        .font(.subheadline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(
                            selected == day
                            ? Color.accentColor
                            : Color(.systemGray6)
                        )
                        .foregroundStyle(
                            selected == day ? .white : .primary
                        )
                        .clipShape(Capsule())
                        .onTapGesture {
                            selected = day
                        }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - 6️⃣ GroupedList

struct GroupedListView: View {
    let items: [GroupedItem]

    var body: some View {
        List {
            ForEach(
                Dictionary(grouping: items, by: { $0.group })
                    .keys.sorted(),
                id: \.self
            ) { key in
                Section(header: Text(key)) {
                    ForEach(items.filter { $0.group == key }) { item in
                        Text(item.title)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - 7️⃣ Map

struct SimpleMapView: View {
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: 0.05,
                        longitudeDelta: 0.05
                    )
                )
            )
        )
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding()
    }
}

// MARK: - 8️⃣ Flow

struct FlowView: View {
    let steps: [FlowItem]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(steps.indices, id: \.self) { index in
                VStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundColor(.white)
                        )

                    Text(steps[index].title)
                        .font(.caption)
                }

                if index < steps.count - 1 {
                    Divider()
                        .frame(height: 2)
                        .overlay(Color.accentColor)
                }
            }
        }
        .padding()
    }
}

// MARK: - 9️⃣ Heatmap

struct HeatmapView: View {
    let values: [[Double]]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(values.indices, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(values[row].indices, id: \.self) { col in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                Color.red.opacity(values[row][col])
                            )
                            .frame(width: 28, height: 28)
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding()
    }
}