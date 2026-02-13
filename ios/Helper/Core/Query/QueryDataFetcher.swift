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
    let checkpointSources: [QuerySource]
    let locationFallbackUsed: Bool

    init(
        timeRange: DateInterval,
        items: [UnifiedItemDTO],
        entries: [QueryResult.Entry],
        missingAccess: [QuerySource],
        checkpointSources: [QuerySource] = [],
        locationFallbackUsed: Bool = false
    ) {
        self.timeRange = timeRange
        self.items = items
        self.entries = entries
        self.missingAccess = missingAccess
        self.checkpointSources = checkpointSources
        self.locationFallbackUsed = locationFallbackUsed
    }
}

struct QueryCollectionOptions: Sendable {
    let shouldCaptureLocation: Bool
    
    init(shouldCaptureLocation: Bool = false) {
        self.shouldCaptureLocation = shouldCaptureLocation
    }
    
    static let `default` = QueryCollectionOptions()
}

protocol QueryDataFetching {
    func collect(days: Int, access: QuerySourceAccessing) async throws -> QueryCollectedData
    func collect(days: Int, access: QuerySourceAccessing, options: QueryCollectionOptions) async throws -> QueryCollectedData
}

final class QueryDataFetcher: QueryDataFetching {

    struct CalendarSnapshot {
        let identifier: String
        let title: String
        let notes: String?
        let location: String?
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
    private let checkpointStore: Etapp2IngestCheckpointStoring
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
        checkpointStore: Etapp2IngestCheckpointStoring? = nil,
        nowProvider: @escaping () -> Date = Date.init,
        eventStore: EKEventStore = EKEventStore()
    ) {
        self.memoryService = memoryService
        self.reminderSyncManager = reminderSyncManager
        self.contactsCollector = contactsCollector ?? ContactsCollectorService(memoryService: memoryService)
        self.photosIndexService = photosIndexService ?? PhotosIndexService(
            memoryService: memoryService,
            sourceConnectionStore: sourceConnectionStore
        )
        self.filesImportService = filesImportService ?? FilesImportService(
            memoryService: memoryService,
            sourceConnectionStore: sourceConnectionStore
        )
        self.locationCollector = locationCollector
        self.sourceConnectionStore = sourceConnectionStore
        self.checkpointStore = checkpointStore ?? Etapp2IngestCheckpointStore(memoryService: memoryService)
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
        checkpointStore: Etapp2IngestCheckpointStoring? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.memoryService = memoryService
        self.reminderSyncManager = reminderSyncManager
        self.contactsCollector = contactsCollector ?? ContactsCollectorService(memoryService: memoryService)
        self.photosIndexService = photosIndexService ?? PhotosIndexService(
            memoryService: memoryService,
            sourceConnectionStore: sourceConnectionStore
        )
        self.filesImportService = filesImportService ?? FilesImportService(
            memoryService: memoryService,
            sourceConnectionStore: sourceConnectionStore
        )
        self.locationCollector = locationCollector
        self.sourceConnectionStore = sourceConnectionStore
        self.checkpointStore = checkpointStore ?? Etapp2IngestCheckpointStore(memoryService: memoryService)
        self.nowProvider = nowProvider
    }
    #endif

    func collect(days: Int, access: QuerySourceAccessing) async throws -> QueryCollectedData {
        return try await collect(days: days, access: access, options: .default)
    }

    func collect(days: Int, access: QuerySourceAccessing, options: QueryCollectionOptions) async throws -> QueryCollectedData {
        let range = Self.timeRange(days: days, now: nowProvider())

        var allItems: [UnifiedItemDTO] = []
        var allEntries: [QueryResult.Entry] = []
        var missingAccess: [QuerySource] = []
        var checkpointSources: [QuerySource] = []
        var locationFallbackUsed = false

        if access.isAllowed(.memory) {
            let result = try fetchMemory(in: range)
            allItems += result.items
            allEntries += result.entries

            let noteResult = try fetchUserNotes(in: range)
            allItems += noteResult.items
            allEntries += noteResult.entries
        } else {
            missingAccess.append(.memory)
        }

        if access.isAllowed(.calendar) {
            let result = fetchCalendar(in: range)
            allItems += result.items
            allEntries += result.entries
        } else {
            missingAccess.append(.calendar)
        }

        if access.isAllowed(.reminders) {
            let result = try await fetchReminders(in: range)
            allItems += result.items
            allEntries += result.entries
        } else {
            missingAccess.append(.reminders)
        }

        if sourceConnectionStore.isEnabled(.contacts) {
            if access.isAllowed(.contacts) {
                _ = try contactsCollector.refreshIndex()
                let checkpoint = try checkpointStore.lastCheckpoint(for: .contacts)
                let result = try contactsCollector.collectDelta(since: checkpoint)
                allItems += result.items
                allEntries += result.entries
                checkpointSources.append(.contacts)
            } else {
                missingAccess.append(.contacts)
            }
        }

        if sourceConnectionStore.isEnabled(.photos) {
            if access.isAllowed(.photos) {
                _ = try await photosIndexService.indexIncremental()
                let checkpoint = try checkpointStore.lastCheckpoint(for: .photos)
                let result = try photosIndexService.collectDelta(since: checkpoint)
                allItems += result.items
                allEntries += result.entries
                checkpointSources.append(.photos)
            } else {
                missingAccess.append(.photos)
            }
        }

        if sourceConnectionStore.isEnabled(.files) {
            if access.isAllowed(.files) {
                let checkpoint = try checkpointStore.lastCheckpoint(for: .files)
                let result = try filesImportService.collectDelta(since: checkpoint)
                allItems += result.items
                allEntries += result.entries
                checkpointSources.append(.files)
            } else {
                missingAccess.append(.files)
            }
        }

        // Location collection (on-demand only)
        if sourceConnectionStore.isEnabled(.location) && options.shouldCaptureLocation {
            if access.isAllowed(.location) {
                if let locationCollector {
                    do {
                        _ = try await locationCollector.captureAndIndex()
                        let checkpoint = try checkpointStore.lastCheckpoint(for: .location)
                        let result = try locationCollector.collectDelta(since: checkpoint)
                        allItems += result.items
                        allEntries += result.entries
                        checkpointSources.append(.location)
                        
                        // Check if fallback was used by looking at last snapshot date
                        if let lastDate = try? locationCollector.lastSnapshotDate(),
                           nowProvider().timeIntervalSince(lastDate) > 60 {
                            locationFallbackUsed = true
                        }
                    } catch {
                        // Location capture failed, but don't fail the whole query
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
            checkpointSources: dedupSources(checkpointSources),
            locationFallbackUsed: locationFallbackUsed
        )
    }

    private func fetchMemory(in range: DateInterval) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        let context = memoryService.context()
        let descriptor = FetchDescriptor<RawEvent>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let rawEvents = try context.fetch(descriptor).filter { range.contains($0.timestamp) }

        let mapped = rawEvents.map(Self.mapRawEvent)
        let entries = rawEvents.map(Self.makeMemoryEntry)
        return (mapped, entries)
    }

    private func fetchUserNotes(in range: DateInterval) throws -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        let context = memoryService.context()
        let descriptor = FetchDescriptor<UserNote>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let notes = try context.fetch(descriptor).filter { range.contains($0.updatedAt) }
        let items = notes.map(Self.mapUserNote)
        let entries = notes.map(Self.makeUserNoteEntry)
        return (items, entries)
    }

    private func fetchCalendar(in range: DateInterval) -> (items: [UnifiedItemDTO], entries: [QueryResult.Entry]) {
        #if canImport(EventKit)
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

    private func dedupSources(_ sources: [QuerySource]) -> [QuerySource] {
        var seen: Set<QuerySource> = []
        var out: [QuerySource] = []
        for source in sources where !seen.contains(source) {
            seen.insert(source)
            out.append(source)
        }
        return out
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

    private static func timeRange(days: Int, now: Date) -> DateInterval {
        let clamped = max(1, min(3650, days))
        let start = Calendar.current.date(byAdding: .day, value: -clamped, to: now) ?? now
        return DateInterval(start: start, end: now)
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

    nonisolated static func mapReminder(_ reminder: ReminderItem, now: Date = Date()) -> UnifiedItemDTO {
        let baseDate = reminder.dueDate ?? now
        return UnifiedItemDTO(
            id: "reminder:\(reminder.id)",
            source: "reminders",
            type: .reminder,
            title: reminder.title,
            body: "",
            createdAt: baseDate,
            updatedAt: baseDate,
            startAt: nil,
            endAt: nil,
            dueAt: reminder.dueDate,
            status: [
                "is_completed": AnyCodable(reminder.isCompleted)
            ]
        )
    }

    nonisolated static func mapCalendarSnapshot(_ event: CalendarSnapshot) -> UnifiedItemDTO {
        let detailParts = [event.location, event.notes]
            .compactMap { value -> String? in
                guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                    return nil
                }
                return trimmed
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
            status: [
                "is_all_day": AnyCodable(event.isAllDay)
            ]
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
            body: nil,
            date: reminder.dueDate
        )
    }

    nonisolated static func makeCalendarEntry(_ snapshot: CalendarSnapshot) -> QueryResult.Entry {
        let detailParts = [snapshot.location, snapshot.notes]
            .compactMap { value -> String? in
                guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                    return nil
                }
                return trimmed
            }

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
        CalendarSnapshot(
            identifier: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Händelse",
            notes: event.notes,
            location: event.location,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            updatedAt: event.lastModifiedDate
        )
    }
    #endif
}
