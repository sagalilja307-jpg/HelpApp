import Foundation
import Combine

struct MemoryOverview {
    let title: String
    let line1: String
    let line2: String
    let updatedAt: Date?
}

enum MemoryTimelineKind {
    case calendar
    case reminder
}

struct MemoryTimelineItem: Identifiable, Hashable {
    let id = UUID()
    let time: Date
    let timeText: String
    let title: String
    let kind: MemoryTimelineKind
}

struct MemoryDaySummary: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let nextText: String
    let chips: [String]
    let bodyLine: String
    let updatedText: String?
}

struct WorkingMemoryDayData {
    let date: Date
    let events: [CalendarEventLite]
    let reminders: [ReminderItem]
    let messages: [GmailMessageSummary]
    let bodyLines: [String]
}

@MainActor
final class ShortTermMemoryCoordinator: ObservableObject {
    @Published private(set) var overview = MemoryOverview(
        title: "Korttidsminne",
        line1: "Inga källor valda.",
        line2: "",
        updatedAt: nil
    )
    @Published private(set) var nextSixHours: [MemoryTimelineItem] = []
    @Published private(set) var daySummaries: [MemoryDaySummary] = []
    @Published private(set) var emptyStateText: String?
    @Published private(set) var isLoading = false

    private let calendar = Calendar.current
    private let gmailOAuthService = GmailOAuthService()
    private let healthSnapshotService = HealthMemorySnapshotService.shared
    private var cachedEvents: [CalendarEventLite] = []
    private var cachedReminders: [ReminderItem] = []
    private var cachedMessages: [GmailMessageSummary] = []
    private var cachedHealthSnapshots: [Date: HealthMemoryDaySnapshot] = [:]
    private var cacheDate: Date?

    func refresh(using settings: MemorySourceSettings) async {
        isLoading = true
        defer { isLoading = false }

        guard settings.anyEnabled else {
            overview = MemoryOverview(
                title: "Korttidsminne",
                line1: "Inga källor valda.",
                line2: "Välj källor för att få överblick i realtid.",
                updatedAt: Date()
            )
            nextSixHours = []
            daySummaries = []
            emptyStateText = "Aktivera minst en källa i Källor för att börja synka korttidsminne."
            cachedEvents = []
            cachedReminders = []
            cachedMessages = []
            cachedHealthSnapshots = [:]
            cacheDate = Date()
            return
        }

        emptyStateText = nil

        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let endOfWindow = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? now

        async let eventsTask = fetchEventsIfEnabled(
            settings.calendarEnabled,
            start: startOfToday,
            end: endOfWindow
        )
        async let remindersTask = fetchRemindersIfEnabled(settings.remindersEnabled)
        async let mailTask = fetchMessagesIfEnabled(settings.mailEnabled)
        async let healthTask = fetchHealthSnapshotsIfEnabled(
            settings.healthEnabled,
            from: startOfToday,
            days: 7
        )

        let events = await eventsTask
        let reminders = await remindersTask
        let messages = await mailTask
        let healthSnapshots = await healthTask

        cachedEvents = events
        cachedReminders = reminders
        cachedMessages = messages
        cachedHealthSnapshots = healthSnapshots
        cacheDate = now

        overview = buildOverview(
            now: now,
            settings: settings,
            events: events,
            reminders: reminders,
            messages: messages,
            todayHealthSnapshot: healthSnapshots[startOfToday]
        )
        nextSixHours = buildNextSixHours(now: now, settings: settings, events: events, reminders: reminders)
        daySummaries = buildDaySummaries(
            from: startOfToday,
            now: now,
            settings: settings,
            events: events,
            reminders: reminders,
            messages: messages,
            healthSnapshots: healthSnapshots
        )
    }

    func loadWorkingDay(_ date: Date, using settings: MemorySourceSettings) async -> WorkingMemoryDayData {
        if cacheDate == nil {
            await refresh(using: settings)
        }

        let dayEvents = settings.calendarEnabled
            ? cachedEvents.filter { calendar.isDate($0.start, inSameDayAs: date) }
            : []

        let dayReminders: [ReminderItem]
        if settings.remindersEnabled {
            dayReminders = cachedReminders.filter { reminder in
                guard let dueDate = reminder.dueDate else {
                    return calendar.isDate(date, inSameDayAs: Date())
                }
                return calendar.isDate(dueDate, inSameDayAs: date)
            }
        } else {
            dayReminders = []
        }

        let dayMessages: [GmailMessageSummary]
        if settings.mailEnabled {
            dayMessages = cachedMessages
                .filter { calendar.isDate($0.internalDate, inSameDayAs: date) }
                .sorted { $0.internalDate > $1.internalDate }
        } else {
            dayMessages = []
        }

        let dayKey = calendar.startOfDay(for: date)
        var healthSnapshot = cachedHealthSnapshots[dayKey]
        if settings.healthEnabled, healthSnapshot == nil {
            healthSnapshot = await healthSnapshotService.fetchSnapshot(for: date, calendar: calendar)
            if let healthSnapshot {
                cachedHealthSnapshots[dayKey] = healthSnapshot
            }
        }

        let bodyLines: [String] = settings.healthEnabled
            ? (healthSnapshot?.detailLines ?? ["Ingen hälsodata för dagen ännu."])
            : []

        return WorkingMemoryDayData(
            date: date,
            events: dayEvents,
            reminders: dayReminders,
            messages: dayMessages,
            bodyLines: bodyLines
        )
    }

    private func fetchEventsIfEnabled(
        _ enabled: Bool,
        start: Date,
        end: Date
    ) async -> [CalendarEventLite] {
        guard enabled else { return [] }
        return await CalendarEventService.shared.fetchEvents(from: start, to: end)
    }

    private func fetchRemindersIfEnabled(_ enabled: Bool) async -> [ReminderItem] {
        guard enabled else { return [] }
        do {
            return try await ReminderSyncManager.shared.fetchActiveReminders()
        } catch {
            return []
        }
    }

    private func fetchMessagesIfEnabled(_ enabled: Bool) async -> [GmailMessageSummary] {
        guard enabled else { return [] }

        guard let token = try? OAuthTokenManager.shared.loadStoredToken() else {
            return []
        }

        let accessToken: String
        if token.isExpired {
            guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
                return []
            }
            do {
                let refreshed = try await gmailOAuthService.refreshAuthorization(refreshToken: refreshToken)
                accessToken = refreshed.accessToken
            } catch {
                return []
            }
        } else {
            accessToken = token.accessToken
        }

        do {
            return try await MailSyncService.shared.fetchMessages(
                accessToken: accessToken,
                gmailQuery: nil,
                maxResults: 50
            )
        } catch {
            return []
        }
    }

    private func fetchHealthSnapshotsIfEnabled(
        _ enabled: Bool,
        from startOfDay: Date,
        days: Int
    ) async -> [Date: HealthMemoryDaySnapshot] {
        guard enabled else { return [:] }

        var snapshots: [Date: HealthMemoryDaySnapshot] = [:]
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfDay) else {
                continue
            }
            let key = calendar.startOfDay(for: day)
            snapshots[key] = await healthSnapshotService.fetchSnapshot(for: day, calendar: calendar)
        }
        return snapshots
    }

    private func buildOverview(
        now: Date,
        settings: MemorySourceSettings,
        events: [CalendarEventLite],
        reminders: [ReminderItem],
        messages: [GmailMessageSummary],
        todayHealthSnapshot: HealthMemoryDaySnapshot?
    ) -> MemoryOverview {
        let todayEvents = events.filter { calendar.isDate($0.start, inSameDayAs: now) }
        let todayDueReminders = reminders.filter { reminder in
            guard let dueDate = reminder.dueDate else { return false }
            return calendar.isDate(dueDate, inSameDayAs: now)
        }
        let unread = messages.filter { $0.isUnread }.count

        let line1Parts: [String] = [
            settings.calendarEnabled ? "\(todayEvents.count) händelser" : nil,
            settings.remindersEnabled ? "\(todayDueReminders.count) uppgifter idag" : nil,
            settings.mailEnabled ? "\(unread) olästa mail" : nil
        ].compactMap { $0 }

        let line2: String
        if settings.healthEnabled {
            if let todayHealthSnapshot {
                line2 = "Hälsa: \(todayHealthSnapshot.overviewLine)"
            } else {
                line2 = "Hälsa: Ingen hälsodata ännu"
            }
        } else {
            line2 = "Hälsa: —"
        }

        return MemoryOverview(
            title: "Idag",
            line1: line1Parts.isEmpty ? "—" : line1Parts.joined(separator: " · "),
            line2: line2,
            updatedAt: now
        )
    }

    private func buildNextSixHours(
        now: Date,
        settings: MemorySourceSettings,
        events: [CalendarEventLite],
        reminders: [ReminderItem]
    ) -> [MemoryTimelineItem] {
        let end = calendar.date(byAdding: .hour, value: 6, to: now) ?? now
        var items: [MemoryTimelineItem] = []

        if settings.calendarEnabled {
            let windowEvents = events.filter { $0.start >= now && $0.start <= end }
            items.append(contentsOf: windowEvents.prefix(8).map { event in
                MemoryTimelineItem(
                    time: event.start,
                    timeText: event.start.formatted(date: .omitted, time: .shortened),
                    title: event.title,
                    kind: .calendar
                )
            })
        }

        if settings.remindersEnabled {
            let dueReminders = reminders
                .compactMap { reminder -> (Date, String)? in
                    guard let dueDate = reminder.dueDate else { return nil }
                    return (dueDate, reminder.title)
                }
                .filter { $0.0 >= now && $0.0 <= end }
                .sorted { $0.0 < $1.0 }

            items.append(contentsOf: dueReminders.prefix(8).map { dueDate, title in
                MemoryTimelineItem(
                    time: dueDate,
                    timeText: dueDate.formatted(date: .omitted, time: .shortened),
                    title: title,
                    kind: .reminder
                )
            })
        }

        return Array(items.sorted { $0.time < $1.time }.prefix(12))
    }

    private func buildDaySummaries(
        from startOfToday: Date,
        now: Date,
        settings: MemorySourceSettings,
        events: [CalendarEventLite],
        reminders: [ReminderItem],
        messages: [GmailMessageSummary],
        healthSnapshots: [Date: HealthMemoryDaySnapshot]
    ) -> [MemoryDaySummary] {
        (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else {
                return nil
            }
            return buildDaySummary(
                date: day,
                now: now,
                settings: settings,
                events: events,
                reminders: reminders,
                messages: messages,
                healthSnapshot: healthSnapshots[calendar.startOfDay(for: day)]
            )
        }
    }

    private func buildDaySummary(
        date: Date,
        now: Date,
        settings: MemorySourceSettings,
        events: [CalendarEventLite],
        reminders: [ReminderItem],
        messages: [GmailMessageSummary],
        healthSnapshot: HealthMemoryDaySnapshot?
    ) -> MemoryDaySummary {
        let dayEvents = settings.calendarEnabled
            ? events.filter { calendar.isDate($0.start, inSameDayAs: date) }
            : []

        let dayReminders = settings.remindersEnabled
            ? reminders.filter { reminder in
                guard let dueDate = reminder.dueDate else { return false }
                return calendar.isDate(dueDate, inSameDayAs: date)
            }
            : []

        let dayUnreadCount = settings.mailEnabled
            ? messages.filter { $0.isUnread && calendar.isDate($0.internalDate, inSameDayAs: date) }.count
            : 0

        let nextText = nextTextForDay(date: date, now: now, events: dayEvents, reminders: dayReminders)

        let healthChip: String? = {
            guard settings.healthEnabled else { return nil }
            if let steps = healthSnapshot?.steps {
                return "Steg \(steps)"
            }
            if let workouts = healthSnapshot?.workoutCount, workouts > 0 {
                return "Pass \(workouts)"
            }
            return "Hälsa"
        }()

        let chips = [
            settings.calendarEnabled ? "Aktiviteter \(dayEvents.count)" : nil,
            settings.remindersEnabled ? "Uppgifter \(dayReminders.count)" : nil,
            settings.mailEnabled ? "Mail \(dayUnreadCount)" : nil,
            healthChip
        ].compactMap { $0 }

        let healthLine: String
        if settings.healthEnabled {
            if let healthSnapshot {
                healthLine = "Hälsa: \(healthSnapshot.overviewLine)"
            } else {
                let isFutureDay = calendar.startOfDay(for: date) > calendar.startOfDay(for: now)
                healthLine = isFutureDay
                    ? "Hälsa: Ingen hälsodata ännu"
                    : "Hälsa: Hälsodata saknas"
            }
        } else {
            healthLine = "Hälsa: —"
        }

        return MemoryDaySummary(
            date: date,
            nextText: nextText,
            chips: chips.isEmpty ? ["—"] : chips,
            bodyLine: healthLine,
            updatedText: "Uppdaterad \(Date().formatted(date: .omitted, time: .shortened))"
        )
    }

    private func nextTextForDay(
        date: Date,
        now: Date,
        events: [CalendarEventLite],
        reminders: [ReminderItem]
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            if let nextEvent = events.first(where: { $0.start >= now }) {
                return "\(nextEvent.start.formatted(date: .omitted, time: .shortened)) \(nextEvent.title)"
            }
            if let nextReminder = reminders
                .compactMap({ reminder -> (Date, String)? in
                    guard let dueDate = reminder.dueDate else { return nil }
                    return (dueDate, reminder.title)
                })
                .filter({ $0.0 >= now })
                .sorted(by: { $0.0 < $1.0 })
                .first {
                return "\(nextReminder.0.formatted(date: .omitted, time: .shortened)) \(nextReminder.1)"
            }
            return "Inget planerat"
        }

        if let firstEvent = events.first {
            return "\(firstEvent.start.formatted(date: .omitted, time: .shortened)) \(firstEvent.title)"
        }
        if let firstReminder = reminders
            .compactMap({ reminder -> (Date, String)? in
                guard let dueDate = reminder.dueDate else { return nil }
                return (dueDate, reminder.title)
            })
            .sorted(by: { $0.0 < $1.0 })
            .first {
            return "\(firstReminder.0.formatted(date: .omitted, time: .shortened)) \(firstReminder.1)"
        }

        return "—"
    }
}
