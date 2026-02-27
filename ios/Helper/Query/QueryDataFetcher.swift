import Foundation
import SwiftData
#if canImport(EventKit)
import EventKit
#endif

struct QueryCollectedData {
    let timeRange: DateInterval
    let items: [UnifiedItemDTO]
    let entries: [QueryResult.Entry]
    let missingAccess: [QuerySource]
    let locationFallbackUsed: Bool

    init(
        timeRange: DateInterval,
        items: [UnifiedItemDTO],
        entries: [QueryResult.Entry],
        missingAccess: [QuerySource],
        locationFallbackUsed: Bool = false
    ) {
        self.timeRange = timeRange
        self.items = items
        self.entries = entries
        self.missingAccess = missingAccess
        self.locationFallbackUsed = locationFallbackUsed
    }
}

struct QueryCollectionOptions: Sendable {
    let shouldCaptureLocation: Bool
    let includeMemory: Bool
    let includeNotes: Bool
    let includeCalendar: Bool
    let includeReminders: Bool
    let includeContacts: Bool
    let includePhotos: Bool
    let includeFiles: Bool

    init(
        shouldCaptureLocation: Bool = false,
        includeMemory: Bool = true,
        includeNotes: Bool = true,
        includeCalendar: Bool = true,
        includeReminders: Bool = true,
        includeContacts: Bool = true,
        includePhotos: Bool = true,
        includeFiles: Bool = true
    ) {
        self.shouldCaptureLocation = shouldCaptureLocation
        self.includeMemory = includeMemory
        self.includeNotes = includeNotes
        self.includeCalendar = includeCalendar
        self.includeReminders = includeReminders
        self.includeContacts = includeContacts
        self.includePhotos = includePhotos
        self.includeFiles = includeFiles
    }

    static let `default` = QueryCollectionOptions()
}

protocol QueryDataFetching {
    func collect(days: Int, access: QuerySourceAccessing) async throws -> QueryCollectedData
    func collect(days: Int, access: QuerySourceAccessing, options: QueryCollectionOptions) async throws -> QueryCollectedData
}

final class QueryDataFetcher: QueryDataFetching {
    private static let contactsRefreshCursorKey = "helper.query.contacts.refresh.last"
    private static let photosRefreshCursorKey = "helper.query.photos.refresh.last"
    private static let contactsRefreshMinInterval: TimeInterval = 5 * 60
    private static let photosRefreshMinInterval: TimeInterval = 60
    private static let locationCaptureMinInterval: TimeInterval = 60
    private static let locationNearNowWindow: TimeInterval = 10 * 60

    struct CalendarSnapshot {
        let identifier: String
        let title: String
        let notes: String?
        let location: String?
        let attendees: [String]
        let status: String?
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool
        let updatedAt: Date?
    }

    private let memoryService: MemoryService
    private let reminderSyncManager: ReminderSyncManager
    private let contactsCollector: ContactsCollecting
    private let photosIndexService: PhotosIndexing
    private let filesImportService: FilesImporting
    private let locationCollector: LocationCollecting?
    private let sourceConnectionStore: SourceConnectionStoring
    private let nowProvider: () -> Date

    #if canImport(EventKit)
    private let eventStore: EKEventStore
    #endif

    #if canImport(EventKit)
    init(
        memoryService: MemoryService,
        reminderSyncManager: ReminderSyncManager = .shared,
        contactsCollector: ContactsCollecting? = nil,
        photosIndexService: PhotosIndexing? = nil,
        filesImportService: FilesImporting? = nil,
        locationCollector: LocationCollecting? = nil,
        sourceConnectionStore: SourceConnectionStoring = SourceConnectionStore.shared,
        nowProvider: @escaping () -> Date = DateService.shared.now,
        eventStore: EKEventStore = EKEventStore()
    ) {
        self.memoryService = memoryService
        self.reminderSyncManager = reminderSyncManager
        self.contactsCollector = contactsCollector ?? ContactsCollectorService()
        self.photosIndexService = photosIndexService ?? PhotosIndexService(
            sourceConnectionStore: sourceConnectionStore
        )
        self.filesImportService = filesImportService ?? FilesImportService(
            textExtractionService: FileTextExtractionService(),
            sourceConnectionStore: sourceConnectionStore
        )
        self.locationCollector = locationCollector
        self.sourceConnectionStore = sourceConnectionStore
        self.nowProvider = nowProvider
        self.eventStore = eventStore
    }
    #else
    init(
        memoryService: MemoryService,
        reminderSyncManager: ReminderSyncManager = .shared,
        contactsCollector: ContactsCollecting? = nil,
        photosIndexService: PhotosIndexing? = nil,
        filesImportService: FilesImporting? = nil,
        locationCollector: LocationCollecting? = nil,
        sourceConnectionStore: SourceConnectionStoring = SourceConnectionStore.shared,
        nowProvider: @escaping () -> Date = DateService.shared.now
    ) {
        self.memoryService = memoryService
        self.reminderSyncManager = reminderSyncManager
        self.contactsCollector = contactsCollector ?? ContactsCollectorService()
        self.photosIndexService = photosIndexService ?? PhotosIndexService(
            sourceConnectionStore: sourceConnectionStore
        )
        self.filesImportService = filesImportService ?? FilesImportService(
            textExtractionService: FileTextExtractionService(),
            sourceConnectionStore: sourceConnectionStore
        )
        self.locationCollector = locationCollector
        self.sourceConnectionStore = sourceConnectionStore
        self.nowProvider = nowProvider
    }
    #endif

    /// New API: collect exactly within the provided `DateInterval`.
    func collect(in range: DateInterval, access: QuerySourceAccessing) async throws -> QueryCollectedData {
        try await collect(in: range, access: access, options: .default)
    }

    /// New API: collect exactly within the provided `DateInterval`.
    func collect(in range: DateInterval, access: QuerySourceAccessing, options: QueryCollectionOptions) async throws -> QueryCollectedData {
        var allItems: [UnifiedItemDTO] = []
        var allEntries: [QueryResult.Entry] = []
        var missingAccess: [QuerySource] = []
        var locationFallbackUsed = false

        if options.includeMemory || options.includeNotes {
            if access.isAllowed(.memory) {
                if options.includeMemory {
                    let result = try fetchMemory(in: range)
                    allItems += result.items
                    allEntries += result.entries
                }
                if options.includeNotes {
                    let noteResult = try fetchUserNotes(in: range)
                    allItems += noteResult.items
                    allEntries += noteResult.entries
                }
            } else {
                missingAccess.append(.memory)
            }
        }

        if options.includeCalendar {
            if access.isAllowed(.calendar) {
                let result = fetchCalendar(in: range)
                allItems += result.items
                allEntries += result.entries
            } else {
                missingAccess.append(.calendar)
            }
        }

        if options.includeReminders {
            if access.isAllowed(.reminders) {
                let result = try await fetchReminders(in: range)
                allItems += result.items
                allEntries += result.entries
            } else {
                missingAccess.append(.reminders)
            }
        }

        if options.includeContacts && sourceConnectionStore.isEnabled(.contacts) {
            if access.isAllowed(.contacts) {
                let context = memoryService.context()
                if try shouldRefreshContactsIndex(in: context) {
                    _ = try contactsCollector.refreshIndex(in: context)
                    markContactsIndexRefreshed()
                }
                let result = try contactsCollector.collectDelta(since: range.start, in: context)
                allItems += result.items
                allEntries += result.entries
            } else {
                missingAccess.append(.contacts)
            }
        }

        if options.includePhotos && sourceConnectionStore.isEnabled(.photos) {
            if access.isAllowed(.photos) {
                let context = memoryService.context()
                if try shouldRefreshPhotosIndex(in: context) {
                    _ = try await photosIndexService.indexIncremental(in: context)
                    markPhotosIndexRefreshed()
                }
                let result = try photosIndexService.collectDelta(since: range.start, in: context)
                allItems += result.items
                allEntries += result.entries
            } else {
                missingAccess.append(.photos)
            }
        }

        if options.includeFiles && sourceConnectionStore.isEnabled(.files) {
            if access.isAllowed(.files) {
                let context = memoryService.context()
                let result = try filesImportService.collectDelta(since: range.start, in: context)
                allItems += result.items
                allEntries += result.entries
            } else {
                missingAccess.append(.files)
            }
        }

        // Location collection (on-demand only)
        if sourceConnectionStore.isEnabled(.location) && options.shouldCaptureLocation {
            if access.isAllowed(.location) {
                if let locationCollector {
                    do {
                        let context = memoryService.context()
                        let now = nowProvider()
                        let needsFreshLocation = range.end >= now.addingTimeInterval(-Self.locationNearNowWindow)
                        let lastSnapshot = try locationCollector.lastSnapshotDate(in: context)
                        let isStale = {
                            guard let lastSnapshot else { return true }
                            return now.timeIntervalSince(lastSnapshot) > Self.locationCaptureMinInterval
                        }()
                        var capturedFreshSnapshot = false

                        if needsFreshLocation && isStale {
                            _ = try await locationCollector.captureAndIndex(in: context)
                            capturedFreshSnapshot = true
                        }

                        let result = try locationCollector.collectDelta(since: range.start, in: context)
                        allItems += result.items
                        allEntries += result.entries

                        let freshnessReferenceDate: Date?
                        if capturedFreshSnapshot {
                            freshnessReferenceDate = try? locationCollector.lastSnapshotDate(in: context)
                        } else {
                            freshnessReferenceDate = lastSnapshot ?? (try? locationCollector.lastSnapshotDate(in: context))
                        }

                        if let lastDate = freshnessReferenceDate,
                           now.timeIntervalSince(lastDate) > 60 {
                            locationFallbackUsed = true
                        }
                    } catch {
                        missingAccess.append(.location)
                    }
                }
            } else {
                missingAccess.append(.location)
            }
        }

        return QueryCollectedData(
            timeRange: range,
            items: dedup(items: allItems),
            entries: allEntries.sorted(by: Self.sortEntriesDescending),
            missingAccess: missingAccess,
            locationFallbackUsed: locationFallbackUsed
        )
    }

    // Backwards-compatible API: wrap days-based collection by building a DateInterval
    func collect(days: Int, access: QuerySourceAccessing) async throws -> QueryCollectedData {
        try await collect(days: days, access: access, options: .default)
    }

    func collect(days: Int, access: QuerySourceAccessing, options: QueryCollectionOptions) async throws -> QueryCollectedData {
        let now = nowProvider()
        let range = Self.timeRange(days: days, now: now)
        return try await collect(in: range, access: access, options: options)
    }

    private func fetchMemory(in range: DateInterval) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        let context = memoryService.context()
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<RawEvent>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp <= end },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let rawEvents = try context.fetch(descriptor)

        let mapped = rawEvents.map(Self.mapRawEvent)
        let entries = rawEvents.map(Self.makeMemoryEntry)
        return (mapped, entries)
    }

    private func fetchUserNotes(in range: DateInterval) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        let context = memoryService.context()
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<UserNote>(
            predicate: #Predicate { $0.updatedAt >= start && $0.updatedAt <= end },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let notes = try context.fetch(descriptor)
        let items = notes.map(Self.mapUserNote)
        let entries = notes.map(Self.makeUserNoteEntry)
        return (items, entries)
    }

    private func fetchCalendar(in range: DateInterval) -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        #if canImport(EventKit)

        // ✅ Defensivt: om någon ändå försöker läsa utan read access, returnera tomt.
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            guard status == .fullAccess else { return ([], []) }
        } else {
            guard status == .authorized else { return ([], []) }
        }

        let predicate = eventStore.predicateForEvents(
            withStart: range.start,
            end: range.end,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)
        let snapshots = events.map(Self.snapshot(from:))
        let items = snapshots.map(Self.mapCalendarSnapshot)
        let entries = snapshots.map(Self.makeCalendarEntry)
        return (items, entries)
        #else
        return ([], [])
        #endif
    }

    private func fetchReminders(in range: DateInterval) async throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        #if canImport(EventKit)
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(iOS 17.0, *) {
            guard status == .fullAccess || status == .writeOnly else { return ([], []) }
        } else {
            guard status == .authorized else { return ([], []) }
        }
        #endif

        let reminders = try await reminderSyncManager.fetchActiveReminders()
        let filtered = reminders.filter { reminder in
            guard let dueDate = reminder.dueDate else { return true }
            return dueDate >= range.start && dueDate <= range.end
        }

        let now = nowProvider()
        let items = filtered.map { Self.mapReminder($0, now: now) }
        let entries = filtered.map(Self.makeReminderEntry)
        return (items, entries)
    }

    private func shouldRefreshContactsIndex(in context: ModelContext) throws -> Bool {
        if Self.shouldRunRefresh(
            cursorKey: Self.contactsRefreshCursorKey,
            minimumInterval: Self.contactsRefreshMinInterval,
            now: nowProvider()
        ) {
            return true
        }

        var descriptor = FetchDescriptor<IndexedContact>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).isEmpty
    }

    private func shouldRefreshPhotosIndex(in context: ModelContext) throws -> Bool {
        if Self.shouldRunRefresh(
            cursorKey: Self.photosRefreshCursorKey,
            minimumInterval: Self.photosRefreshMinInterval,
            now: nowProvider()
        ) {
            return true
        }

        var descriptor = FetchDescriptor<IndexedPhotoAsset>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).isEmpty
    }

    private func markContactsIndexRefreshed() {
        UserDefaults.standard.set(nowProvider(), forKey: Self.contactsRefreshCursorKey)
    }

    private func markPhotosIndexRefreshed() {
        UserDefaults.standard.set(nowProvider(), forKey: Self.photosRefreshCursorKey)
    }

    private static func shouldRunRefresh(
        cursorKey: String,
        minimumInterval: TimeInterval,
        now: Date
    ) -> Bool {
        guard let previous = UserDefaults.standard.object(forKey: cursorKey) as? Date else {
            return true
        }
        return now.timeIntervalSince(previous) >= minimumInterval
    }

    private func dedup(items: [UnifiedItemDTO]) -> [UnifiedItemDTO] {
        var seen: Set<String> = []
        var deduped: [UnifiedItemDTO] = []

        for item in items {
            guard !seen.contains(item.id) else { continue }
            seen.insert(item.id)
            deduped.append(item)
        }

        return deduped
    }

    private static func sortEntriesDescending(_ lhs: QueryResult.Entry, _ rhs: QueryResult.Entry) -> Bool {
        switch (lhs.date, rhs.date) {
        case let (l?, r?):
            return l > r
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.title < rhs.title
        }
    }

    /// ✅ Viktig fix: inkludera framtid, annars får du aldrig “imorgon/nästa vecka”
    private static func timeRange(days: Int, now: Date) -> DateInterval {
        // Include the past N days up to the end of today, and a small future window (tomorrow) to catch upcoming items
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -max(1, days), to: now) ?? now
        // End at end of next day to ensure we capture "tomorrow/next week" style items
        let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        let end = calendar.date(byAdding: .day, value: 1, to: endOfToday) ?? endOfToday
        return DateInterval(start: start, end: end)
    }
}

extension QueryDataFetcher {
    nonisolated static func mapRawEvent(_ event: RawEvent) -> UnifiedItemDTO {
        let title = event.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .first
            .map(String.init)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "Minne från \(event.source)"

        let body = (event.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? event.text ?? ""
            : event.payloadJSON

        return UnifiedItemDTO(
            id: "memory:\(event.id)",
            source: "notes",
            type: .note,
            title: title,
            body: body,
            createdAt: event.timestamp,
            updatedAt: event.createdAt,
            startAt: nil,
            endAt: nil,
            dueAt: nil,
            status: [
                "memory_source": AnyCodable(event.source)
            ]
        )
    }

    nonisolated static func mapUserNote(_ note: UserNote) -> UnifiedItemDTO {
        UnifiedItemDTO(
            id: "note:\(note.id)",
            source: "notes",
            type: .note,
            title: note.title,
            body: note.body,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            startAt: nil,
            endAt: nil,
            dueAt: nil,
            status: [
                "note_source": AnyCodable(note.source),
                "external_ref": AnyCodable(note.externalRef ?? "")
            ]
        )
    }

    nonisolated static func mapReminder(
        _ reminder: ReminderItem,
        now: Date = Date()
    ) -> UnifiedItemDTO {
        let baseDate = reminder.dueDate ?? now
        let body = reminderBody(reminder) ?? ""
        let priorityLabel = reminderPriorityLabel(reminder.priority)

        var status: [String: AnyCodable] = [
            "is_completed": AnyCodable(reminder.isCompleted)
        ]
        if let priorityLabel {
            status["priority"] = AnyCodable(priorityLabel)
        }

        return UnifiedItemDTO(
            id: "reminder:\(reminder.id)",
            source: "reminders",
            type: .reminder,
            title: reminder.title,
            body: body,
            createdAt: baseDate,
            updatedAt: baseDate,
            startAt: nil,
            endAt: nil,
            dueAt: reminder.dueDate,
            status: status
        )
    }

    nonisolated static func mapCalendarSnapshot(_ event: CalendarSnapshot) -> UnifiedItemDTO {
        let detailParts = calendarDetailLines(event)
        var status: [String: AnyCodable] = [
            "is_all_day": AnyCodable(event.isAllDay)
        ]
        if let eventStatus = event.status {
            status["event_status"] = AnyCodable(eventStatus)
        }

        return UnifiedItemDTO(
            id: "calendar:\(event.identifier)",
            source: "calendar",
            type: .event,
            title: event.title,
            body: detailParts.joined(separator: "\n"),
            createdAt: event.startDate,
            updatedAt: event.updatedAt ?? event.startDate,
            startAt: event.startDate,
            endAt: event.endDate,
            dueAt: nil,
            status: status
        )
    }

    nonisolated static func makeMemoryEntry(_ event: RawEvent) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(),
            source: .memory,
            title: mapRawEvent(event).title,
            body: mapRawEvent(event).body,
            date: event.timestamp
        )
    }

    nonisolated static func makeUserNoteEntry(_ note: UserNote) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(),
            source: .memory,
            title: note.title,
            body: note.body,
            date: note.updatedAt
        )
    }

    nonisolated static func makeReminderEntry(_ reminder: ReminderItem) -> QueryResult.Entry {
        QueryResult.Entry(
            id: UUID(),
            source: .reminders,
            title: reminder.title,
            body: reminderBody(reminder),
            date: reminder.dueDate
        )
    }

    nonisolated static func makeCalendarEntry(_ snapshot: CalendarSnapshot) -> QueryResult.Entry {
        let detailParts = calendarDetailLines(snapshot)

        return QueryResult.Entry(
            id: UUID(),
            source: .calendar,
            title: snapshot.title,
            body: detailParts.isEmpty ? nil : detailParts.joined(separator: "\n"),
            date: snapshot.startDate
        )
    }

    #if canImport(EventKit)
    nonisolated static func snapshot(from event: EKEvent) -> CalendarSnapshot {
        let attendeeNames: [String] = (event.attendees ?? [])
            .compactMap { attendee in
                participantToken(from: attendee)
            }

        return CalendarSnapshot(
            identifier: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Händelse",
            notes: event.notes,
            location: event.location,
            attendees: attendeeNames,
            status: calendarEventStatus(event.status),
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            updatedAt: event.lastModifiedDate
        )
    }
    #endif

    nonisolated static func reminderBody(_ reminder: ReminderItem) -> String? {
        var lines: [String] = []
        lines.append("Status: \(reminder.isCompleted ? "completed" : "pending")")

        if let priority = reminderPriorityLabel(reminder.priority) {
            lines.append("Prioritet: \(priority)")
        }

        if let location = cleanedText(reminder.location) {
            lines.append("Plats: \(location)")
        }

        if let notes = cleanedText(reminder.notes) {
            lines.append(notes)
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    nonisolated static func reminderPriorityLabel(_ priority: Int?) -> String? {
        guard let priority, priority > 0 else { return nil }
        switch priority {
        case 1...4:
            return "high"
        case 5:
            return "medium"
        default:
            return "low"
        }
    }

    nonisolated static func calendarDetailLines(_ snapshot: CalendarSnapshot) -> [String] {
        var lines: [String] = []

        if let location = cleanedText(snapshot.location) {
            lines.append("Plats: \(location)")
        }
        if !snapshot.attendees.isEmpty {
            lines.append("Deltagare: \(snapshot.attendees.joined(separator: ", "))")
        }
        if let status = cleanedText(snapshot.status) {
            lines.append("Status: \(status)")
        }
        if let notes = cleanedText(snapshot.notes) {
            lines.append(notes)
        }

        return lines
    }

    #if canImport(EventKit)
    nonisolated static func participantToken(from participant: EKParticipant) -> String? {
        if let name = cleanedText(participant.name) {
            return name
        }
        let absolute = participant.url.absoluteString
        if let mail = cleanedText(absolute.replacingOccurrences(of: "mailto:", with: "")) {
            return mail
        }
        return nil
    }

    nonisolated static func calendarEventStatus(_ status: EKEventStatus) -> String {
        switch status {
        case .confirmed:
            return "confirmed"
        case .tentative:
            return "tentative"
        case .canceled:
            return "cancelled"
        default:
            return "unknown"
        }
    }
    #endif

    nonisolated static func cleanedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
