import SwiftUI

struct WorkingMemoryDayView: View {
    let date: Date

    @EnvironmentObject private var settings: MemorySourceSettings
    @EnvironmentObject private var coordinator: ShortTermMemoryCoordinator

    @State private var dayData: WorkingMemoryDayData?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                    .ios26Card()

                if let dayData {
                    if settings.calendarEnabled {
                        section(title: "Kalender", systemImage: "calendar") {
                            if dayData.events.isEmpty {
                                ContentUnavailableView("Inga händelser", systemImage: "calendar.badge.clock")
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(dayData.events) { event in
                                        DayRow(
                                            left: event.start.formatted(date: .omitted, time: .shortened),
                                            title: event.title,
                                            right: event.end.formatted(date: .omitted, time: .shortened)
                                        )
                                    }
                                }
                            }
                        }
                        .ios26Card()
                    }

                    if settings.remindersEnabled {
                        section(title: "Påminnelser", systemImage: "checklist") {
                            if dayData.reminders.isEmpty {
                                ContentUnavailableView("Inga aktiva uppgifter", systemImage: "checkmark.circle")
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(dayData.reminders, id: \.id) { reminder in
                                        DayRow(
                                            left: reminder.dueDate?.formatted(date: .omitted, time: .shortened) ?? "—",
                                            title: reminder.title,
                                            right: ""
                                        )
                                    }
                                }
                            }
                        }
                        .ios26Card()
                    }

                    if settings.mailEnabled {
                        section(title: "Mail", systemImage: "envelope") {
                            let unreadMessages = dayData.messages.filter { $0.isUnread }
                            if unreadMessages.isEmpty {
                                ContentUnavailableView("Inga olästa", systemImage: "envelope.open")
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(unreadMessages.prefix(20), id: \.id) { message in
                                        DayRow(
                                            left: message.internalDate.formatted(date: .omitted, time: .shortened),
                                            title: message.subject.isEmpty ? message.snippet : message.subject,
                                            right: message.from
                                        )
                                    }
                                }
                            }
                        }
                        .ios26Card()
                    }

                    if settings.healthEnabled {
                        section(title: "Kropp", systemImage: "heart") {
                            if dayData.bodyLines.isEmpty {
                                ContentUnavailableView("Ingen data", systemImage: "heart.slash")
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(dayData.bodyLines, id: \.self) { line in
                                        Text(line)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .ios26Card(sensitive: true)
                    }
                } else {
                    ContentUnavailableView("Laddar…", systemImage: "clock")
                        .ios26Card()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(IOS26Style.pageBackground)
        .navigationTitle("Arbetsminne")
        .navigationBarTitleDisplayMode(.large)
        .task {
            dayData = await coordinator.loadWorkingDay(date, using: settings)
        }
        .onChange(of: settings.calendarEnabled) { _, _ in
            Task { dayData = await coordinator.loadWorkingDay(date, using: settings) }
        }
        .onChange(of: settings.remindersEnabled) { _, _ in
            Task { dayData = await coordinator.loadWorkingDay(date, using: settings) }
        }
        .onChange(of: settings.mailEnabled) { _, _ in
            Task { dayData = await coordinator.loadWorkingDay(date, using: settings) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                .font(.title2.weight(.semibold))

            Text("Detaljer per källa, baserat på det du har synkat.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            content()
        }
    }
}

private struct DayRow: View {
    let left: String
    let title: String
    let right: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(left)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)

            Spacer()

            if !right.isEmpty {
                Text(right)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.thinMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.55), lineWidth: 0.5)
        )
    }
}
