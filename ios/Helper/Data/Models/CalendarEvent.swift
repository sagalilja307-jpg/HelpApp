// CalendarEvent.swift
// SwiftUI-compatible wrapper for EKEvent

import Foundation
import EventKit
import SwiftUI

/// A lightweight wrapper around EKEvent for use in SwiftUI views.
public struct CalendarEvent: Identifiable, Hashable {

    // MARK: - Public Properties

    public let id: String               // Used for SwiftUI identification
    public let title: String
    public let notes: String?
    public let location: String?
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let calendarTitle: String
    public let calendarColor: Color
    public let ekIdentifier: String?    // Original EKEvent identifier (for editing/deletion)

    // MARK: - Initializers

    /// Initializes from an EKEvent instance.
    public init(from ek: EKEvent) {
        self.id = ek.eventIdentifier
        self.title = ek.title ?? "Händelse"
        self.notes = ek.notes
        self.location = ek.location
        self.startDate = ek.startDate
        self.endDate = ek.endDate
        self.isAllDay = ek.isAllDay
        self.calendarTitle = ek.calendar.title
        self.calendarColor = Color(UIColor(cgColor: ek.calendar.cgColor)) // UIKit -> SwiftUI
        self.ekIdentifier = ek.eventIdentifier
    }

    /// Manual initializer (used for previews, testing, or mock data)
    public init(
        id: String,
        title: String,
        notes: String?,
        location: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarTitle: String,
        calendarColor: Color,
        ekIdentifier: String?
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.calendarColor = calendarColor
        self.ekIdentifier = ekIdentifier
    }
}
