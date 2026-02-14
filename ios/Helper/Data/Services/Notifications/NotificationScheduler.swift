// NotificationScheduler.swift

import Foundation
import UserNotifications

final class NotificationScheduler {

    static let shared = NotificationScheduler()

    private init() {}

    func scheduleSuggestionNotification(suggestion: ActionSuggestion) {
        let content = UNMutableNotificationContent()
        content.title = suggestion.title ?? "Ny åtgärd föreslås"
        content.body = suggestion.explanation
        content.sound = .default

        // 🆕 Differentiera follow-up
        content.categoryIdentifier = (suggestion.type == .followUp)
            ? "FOLLOW_UP"
            : "ACTION_SUGGESTION"

        // Lagra info för hantering
        content.userInfo = [
            "suggestion_id": suggestion.id.uuidString,
            "content_id": suggestion.contentId.uuidString,
            "type": String(describing: suggestion.type)
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)

        let request = UNNotificationRequest(
            identifier: suggestion.id.uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }
}


