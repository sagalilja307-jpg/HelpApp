// FollowUpItem.swift

import Foundation

enum FollowUpStatus: String, Codable {
    case open
    case completed
    case dismissed
}

struct FollowUpItem: Identifiable, Equatable {

    let id: UUID

    /// Human-readable description
    let title: String

    /// Link back to original content
    let contentId: UUID

    /// Optional links
    let relatedCalendarEventId: String?
    let relatedReminderId: String?

    /// State
    var status: FollowUpStatus

    /// Metadata
    let createdAt: Date
    var completedAt: Date?

    init(
        title: String,
        contentId: UUID,
        relatedCalendarEventId: String? = nil,
        relatedReminderId: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.contentId = contentId
        self.relatedCalendarEventId = relatedCalendarEventId
        self.relatedReminderId = relatedReminderId
        self.status = .open
        self.createdAt = Date()
        self.completedAt = nil
    }
}
