// DateFormatterHelper.swift
// Provides shared localized DateFormatters for Swedish locale

import Foundation

/// A collection of static DateFormatters for consistent Swedish date formatting throughout the app.
struct DateFormatterHelper {

    /// Prevent instantiation
    private init() {}

    // MARK: - Standard Swedish Formatters

    /// Full date, e.g. "27 november 2025"
    static let fullDateFormatter: DateFormatter = {
        DateService.shared.dateFormatter(
            dateStyle: .long
        )
    }()

    /// Month and year, e.g. "November 2025"
    static let monthFormatter: DateFormatter = {
        DateService.shared.dateFormatter(
            dateFormat: "MMMM yyyy"
        )
    }()

    /// Weekday, e.g. "Måndag"
    static let weekdayFormatter: DateFormatter = {
        DateService.shared.dateFormatter(
            dateFormat: "EEEE"
        )
    }()

    /// Day number, e.g. "27"
    static let dayNumberFormatter: DateFormatter = {
        DateService.shared.dateFormatter(
            dateFormat: "d"
        )
    }()

    /// ISO date string, e.g. "2025-11-27"
    static let isoDateFormatter: DateFormatter = {
        DateService.shared.dateFormatter(
            dateFormat: "yyyy-MM-dd"
        )
    }()
}
