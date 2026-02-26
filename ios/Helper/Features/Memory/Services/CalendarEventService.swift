import EventKit
import Foundation

struct CalendarEventLite: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
}

final class CalendarEventService {
    static let shared = CalendarEventService()

    private let store = EKEventStore()

    private init() {}

    func fetchEvents(from start: Date, to end: Date) async -> [CalendarEventLite] {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            guard status == .fullAccess else {
                return []
            }
        } else {
            guard status == .authorized else {
                return []
            }
        }

        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)

        return store
            .events(matching: predicate)
            .map { event in
                CalendarEventLite(
                    id: event.eventIdentifier ?? "\(event.startDate.timeIntervalSince1970)-\(event.title ?? "event")",
                    title: event.title ?? "Händelse",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay
                )
            }
            .sorted { $0.start < $1.start }
    }
}
