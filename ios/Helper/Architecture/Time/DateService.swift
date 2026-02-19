import Foundation

public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}

    public func now() -> Date { Date() }
}

public struct DateService: Sendable {
    public nonisolated static let shared = DateService()

    public let clock: any Clock
    public let calendar: Calendar
    public let locale: Locale
    public let timeZone: TimeZone

    public init(
        clock: any Clock = SystemClock(),
        locale: Locale = Locale(identifier: "sv_SE"),
        timeZone: TimeZone = .current
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone

        self.clock = clock
        self.calendar = calendar
        self.locale = locale
        self.timeZone = timeZone
    }

    public func now() -> Date {
        clock.now()
    }

    public nonisolated func date(byAdding component: Calendar.Component, value: Int, to date: Date) -> Date? {
        calendar.date(byAdding: component, value: value, to: date)
    }

    public nonisolated func dateComponents(
        _ components: Set<Calendar.Component>,
        from date: Date
    ) -> DateComponents {
        calendar.dateComponents(components, from: date)
    }

    public nonisolated func dateComponents(
        _ components: Set<Calendar.Component>,
        from start: Date,
        to end: Date
    ) -> DateComponents {
        calendar.dateComponents(components, from: start, to: end)
    }

    public nonisolated func dateFormatter(
        dateStyle: DateFormatter.Style = .none,
        timeStyle: DateFormatter.Style = .none,
        dateFormat: String? = nil,
        locale: Locale? = nil,
        timeZone: TimeZone? = nil
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale ?? self.locale
        formatter.timeZone = timeZone ?? self.timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        if let dateFormat {
            formatter.dateFormat = dateFormat
        }
        return formatter
    }

    public nonisolated func parseISO8601(_ value: String) -> Date? {
        let fractionalFormatter = Self.makeISO8601Formatter(includeFractionalSeconds: true)
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        let standardFormatter = Self.makeISO8601Formatter(includeFractionalSeconds: false)
        return standardFormatter.date(from: value)
    }

    public nonisolated func formatISO8601(_ date: Date, includeFractionalSeconds: Bool = true) -> String {
        let formatter = Self.makeISO8601Formatter(includeFractionalSeconds: includeFractionalSeconds)
        return formatter.string(from: date)
    }

    private nonisolated static func makeISO8601Formatter(
        includeFractionalSeconds: Bool
    ) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        if includeFractionalSeconds {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        } else {
            formatter.formatOptions = [.withInternetDateTime]
        }
        return formatter
    }
}
