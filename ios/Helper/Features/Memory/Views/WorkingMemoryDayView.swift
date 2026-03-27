import SwiftUI
import UIKit

struct WorkingMemoryDayView: View {
    let date: Date
    private let followUpCoordinator: FollowUpCoordinating

    @EnvironmentObject private var settings: MemorySourceSettings
    @EnvironmentObject private var coordinator: ShortTermMemoryCoordinator

    @State private var dayData: WorkingMemoryDayData?
    @State private var isLoading = false
    @State private var followUpDraft: FollowUpPresentation?
    @State private var sharePresentation: ShareTextPresentation?

    init(
        date: Date,
        followUpCoordinator: FollowUpCoordinating
    ) {
        self.date = date
        self.followUpCoordinator = followUpCoordinator
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: IOS26Style.Spacing.sm) {
                header
                    .ios26Card()

                if let dayData {
                    if !dayData.followUps.isEmpty {
                        section(title: "Uppföljningar", systemImage: "bell.badge") {
                            VStack(spacing: 12) {
                                ForEach(dayData.followUps) { followUp in
                                    followUpRow(followUp)
                                }
                            }
                        }
                        .ios26Card()
                    }

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
                        section(title: "Hälsa", systemImage: "heart") {
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
        .navigationTitle("Arbetsminne")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $followUpDraft) { presentation in
            FollowUpComposerSheet(
                draft: presentation.draft,
                onCopy: { draft in
                    await copyFollowUpDraft(draft)
                },
                onShare: { draft in
                    await shareFollowUpDraft(draft)
                },
                onMarkSent: { draft in
                    await markFollowUpSent(draft)
                },
                onCancel: {
                    followUpDraft = nil
                }
            )
        }
        .sheet(item: $sharePresentation) { presentation in
            TextShareSheet(text: presentation.text)
        }
        .refreshable {
            await reload()
        }
        .task {
            await reload()
        }
        .onChange(of: settings.calendarEnabled) { _, _ in
            Task { await reload() }
        }
        .onChange(of: settings.remindersEnabled) { _, _ in
            Task { await reload() }
        }
        .onChange(of: settings.mailEnabled) { _, _ in
            Task { await reload() }
        }
        .onChange(of: settings.healthEnabled) { _, _ in
            Task { await reload() }
        }
        .animation(.snappy, value: dayData?.events.count ?? 0)
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        dayData = await coordinator.loadWorkingDay(date, using: settings)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                .font(.title2.weight(.semibold))

            Text("Detaljer per källa, baserat på det du har synkat.")
                .font(.body)
                .foregroundStyle(.secondary)

            FlowChips {
                if settings.calendarEnabled { IOS26Style.badge("Kalender", systemImage: "calendar", prominence: .secondary) }
                if settings.remindersEnabled { IOS26Style.badge("Påminnelser", systemImage: "checklist", prominence: .secondary) }
                if settings.mailEnabled { IOS26Style.badge("Mail", systemImage: "envelope", prominence: .secondary) }
                if settings.healthEnabled { IOS26Style.badge("Hälsa", systemImage: "heart", prominence: .sensitive) }
            }
            .padding(.top, 2)
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

    @ViewBuilder
    private func followUpRow(_ followUp: PendingFollowUpSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(followUp.dueAt.formatted(date: .omitted, time: .shortened))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(followUp.title)
                        .font(.body.weight(.medium))

                    if !followUp.contextText.isEmpty {
                        Text(followUp.contextText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 10)
            }

            HStack(spacing: 8) {
                Button("Skicka nu") {
                    followUpDraft = FollowUpPresentation(draft: .init(snapshot: followUp))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Inte nu") {
                    Task {
                        _ = try? await followUpCoordinator.snoozeFollowUp(id: followUp.id)
                        await reload()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .ios26Pill()
    }

    private func copyFollowUpDraft(_ draft: FollowUpComposerDraft) async {
        let messageID = draft.sourceMessageID ?? draft.id ?? UUID().uuidString
        guard let saved = try? await followUpCoordinator.saveFollowUpDraft(
            draft,
            defaultSourceMessageID: messageID,
            logMessageID: draft.id ?? messageID,
            reasons: ["trigger:working_memory", "action_kind:follow_up", "due_policy:24h_then_next_09"]
        ) else {
            return
        }

        UIPasteboard.general.string = saved.draftText
        followUpDraft = nil
        await reload()
    }

    private func shareFollowUpDraft(_ draft: FollowUpComposerDraft) async {
        let messageID = draft.sourceMessageID ?? draft.id ?? UUID().uuidString
        guard let saved = try? await followUpCoordinator.saveFollowUpDraft(
            draft,
            defaultSourceMessageID: messageID,
            logMessageID: draft.id ?? messageID,
            reasons: ["trigger:working_memory", "action_kind:follow_up", "due_policy:24h_then_next_09"]
        ) else {
            return
        }

        sharePresentation = ShareTextPresentation(text: saved.draftText)
        followUpDraft = nil
        await reload()
    }

    private func markFollowUpSent(_ draft: FollowUpComposerDraft) async {
        let messageID = draft.sourceMessageID ?? draft.id ?? UUID().uuidString
        _ = try? await followUpCoordinator.markFollowUpCompleted(
            from: draft,
            defaultSourceMessageID: messageID,
            logMessageID: draft.id ?? messageID,
            reasons: ["trigger:working_memory", "action_kind:follow_up", "due_policy:24h_then_next_09"]
        )
        followUpDraft = nil
        await reload()
    }
}

private struct DayRow: View {
    let left: String
    let title: String
    let right: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(left)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 10)

            if !right.isEmpty {
                Text(right)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .ios26Pill()
    }
}

private struct FollowUpPresentation: Identifiable {
    let id: String
    let draft: FollowUpComposerDraft

    init(draft: FollowUpComposerDraft) {
        self.id = draft.id ?? draft.sourceMessageID ?? UUID().uuidString
        self.draft = draft
    }
}

private struct ShareTextPresentation: Identifiable {
    let text: String

    var id: String { text }
}

/// Duplicated here to keep the file self-contained.
private struct FlowChips<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 8)], alignment: .leading, spacing: 8) {
            content()
        }
    }
}
