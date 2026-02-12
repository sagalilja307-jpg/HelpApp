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
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.locale = Locale(identifier: "sv_SE")
        return formatter
    }()

    /// Month and year, e.g. "November 2025"
    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "sv_SE")
        return formatter
    }()

    /// Weekday, e.g. "Måndag"
    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = Locale(identifier: "sv_SE")
        return formatter
    }()

    /// Day number, e.g. "27"
    static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        formatter.locale = Locale(identifier: "sv_SE")
        return formatter
    }()

    /// ISO date string, e.g. "2025-11-27"
    static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "sv_SE")
        return formatter
    }()
}
