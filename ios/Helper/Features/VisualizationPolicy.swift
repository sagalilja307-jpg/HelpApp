import Foundation

public enum VisualizationComponent: Equatable {
    case summaryCards
    case narrative
    case focus
    case timeline
    case weekScroll
    case groupedList
    case map
    case flow
    case heatmap
}

public enum Domain: String {
    case calendar
    case reminders
    case mail
    case contacts
    case files
    case photos
    case location
    case notes
    case memory
}

public enum Operation: String {
    case count
    case list
    case exists
    case sum
    case latest
}

public struct TimeScope {

    public enum ScopeType {
        case all
        case relative(String)
        case absolute
    }

    public let type: ScopeType

    public var isLongRange: Bool {
        switch type {

        case .all:
            return true

        case .absolute:
            return false

        case .relative(let value):
            let longValues: Set<String> = [
                "7d", "30d", "3m", "1y"
            ]
            return longValues.contains(value)
        }
    }
}

public struct VisualizationPolicy {

    public static func resolve(
        domain: Domain,
        operation: Operation,
        timeScope: TimeScope
    ) -> VisualizationComponent {

        switch operation {

        case .count:
            return .summaryCards

        case .exists:
            return .narrative

        case .latest:
            return .focus

        case .sum:
            return resolveSum(timeScope: timeScope)

        case .list:
            return resolveList(domain: domain, timeScope: timeScope)
        }
    }

    // MARK: SUM (följer din tabell)

    private static func resolveSum(
        timeScope: TimeScope
    ) -> VisualizationComponent {

        return timeScope.isLongRange
            ? .heatmap
            : .summaryCards
    }

    // MARK: LIST (följer din första stora tabell exakt)

    private static func resolveList(
        domain: Domain,
        timeScope: TimeScope
    ) -> VisualizationComponent {

        let long = timeScope.isLongRange

        switch domain {

        case .calendar:
            return long ? .weekScroll : .timeline

        case .mail:
            return long ? .groupedList : .timeline

        case .photos:
            return long ? .groupedList : .timeline

        case .memory:
            return long ? .groupedList : .timeline

        case .reminders:
            return long ? .groupedList : .flow

        case .location:
            return .map

        case .notes:
            return .groupedList

        case .files:
            return .groupedList

        case .contacts:
            return .groupedList
        }
    }
}