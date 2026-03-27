import Foundation

enum ChatSuggestionKind: String, Sendable, Codable, Equatable {
    case calendar
    case reminder
    case note
    case followUp

    var badgeTitle: String {
        switch self {
        case .calendar:
            return "Kalender"
        case .reminder:
            return "Påminnelse"
        case .note:
            return "Anteckning"
        case .followUp:
            return "Uppföljning"
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .calendar:
            return "Lägg i kalender"
        case .reminder:
            return "Skapa påminnelse"
        case .note:
            return "Spara som anteckning"
        case .followUp:
            return "Planera uppföljning"
        }
    }
}

enum ChatSuggestionState: Sendable, Equatable {
    case visible
    case dismissed
    case executing
    case completed
    case failed(String)
}

enum ChatSuggestionReminderPriority: String, Sendable, Codable, CaseIterable, Equatable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .high:
            return "Hög"
        case .medium:
            return "Medel"
        case .low:
            return "Låg"
        }
    }

    var eventKitValue: Int {
        switch self {
        case .high:
            return 1
        case .medium:
            return 5
        case .low:
            return 9
        }
    }
}

enum ChatSuggestionDraft: Sendable, Equatable {
    struct CalendarDraft: Sendable, Equatable {
        let title: String
        let notes: String
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool
    }

    struct ReminderDraft: Sendable, Equatable {
        let title: String
        let dueDate: Date?
        let notes: String
        let location: String?
        let priority: ChatSuggestionReminderPriority?
    }

    struct NoteDraft: Sendable, Equatable {
        let title: String
        let body: String

        static let empty = NoteDraft(title: "", body: "")
    }

    struct FollowUpDraft: Sendable, Equatable {
        let title: String
        let draftText: String
        let contextText: String
        let waitingSince: Date
        let eligibleAt: Date
        let dueAt: Date
        let clusterID: String?
    }

    case calendar(CalendarDraft)
    case reminder(ReminderDraft)
    case note(NoteDraft)
    case followUp(FollowUpDraft)
}

struct ChatSuggestionCard: Sendable, Equatable {
    let kind: ChatSuggestionKind
    let title: String
    let explanation: String
    let draft: ChatSuggestionDraft
    let state: ChatSuggestionState
    let confidence: Double
    let auditReasons: [String]

    var primaryActionTitle: String { kind.primaryActionTitle }

    func updating(state: ChatSuggestionState) -> ChatSuggestionCard {
        ChatSuggestionCard(
            kind: kind,
            title: title,
            explanation: explanation,
            draft: draft,
            state: state,
            confidence: confidence,
            auditReasons: auditReasons
        )
    }
}

enum ChatSuggestionDecision: Sendable, Equatable {
    case suggestion(ChatSuggestionCard)
    case suppressed(
        kind: ChatSuggestionKind?,
        confidence: Double?,
        reasons: [String]
    )
    case noAction(reasons: [String])
}

protocol ChatSuggestionEvaluating: Sendable {
    func decide(for text: String) -> ChatSuggestionDecision
}

struct ChatSuggestionPolicy: Sendable, Equatable {
    let isEnabled: Bool
    let minimumConfidence: Double
    let maximumSuggestionsPerTurn: Int

    static let cautiousChat = ChatSuggestionPolicy(
        isEnabled: true,
        minimumConfidence: 0.75,
        maximumSuggestionsPerTurn: 1
    )
}
