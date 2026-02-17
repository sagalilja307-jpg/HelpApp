import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(EventKit)
import EventKit
#endif

protocol CalendarFeatureBuilding {
    func buildFeatures(in interval: DateInterval) async throws -> [CalendarFeatureEventIngestDTO]
}

final class CalendarFeatureBuilder: CalendarFeatureBuilding {

    #if canImport(EventKit)
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }
    #else
    init() {}
    #endif

    func buildFeatures(in interval: DateInterval) async throws -> [CalendarFeatureEventIngestDTO] {
        #if canImport(EventKit)
        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )
        let events = eventStore.events(matching: predicate)
        return events.compactMap(Self.mapEvent)
        #else
        return []
        #endif
    }

    #if canImport(EventKit)
    private static func mapEvent(_ event: EKEvent) -> CalendarFeatureEventIngestDTO? {
        let identifier = event.eventIdentifier ?? UUID().uuidString
        let title = event.title ?? "Händelse"
        guard let startAt = event.startDate else {
            return nil
        }
        let endAt = event.endDate ?? startAt
        let snapshotID = "calendar:\(identifier):\(Self.isoFormatter.string(from: startAt))"

        let hashInput = [
            identifier,
            title,
            event.notes ?? "",
            event.location ?? "",
            Self.isoFormatter.string(from: startAt),
            Self.isoFormatter.string(from: endAt),
            event.isAllDay ? "1" : "0",
            event.calendar.title,
            event.lastModifiedDate.map(Self.isoFormatter.string(from:)) ?? "",
        ].joined(separator: "|")

        return CalendarFeatureEventIngestDTO(
            id: snapshotID,
            eventIdentifier: identifier,
            title: title,
            notes: event.notes,
            location: event.location,
            startAt: startAt,
            endAt: endAt,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar.title,
            lastModifiedAt: event.lastModifiedDate,
            snapshotHash: "sha256:\(Self.sha256(hashInput))"
        )
    }
    #endif

    private static func sha256(_ text: String) -> String {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        return String(text.hashValue, radix: 16)
        #endif
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
