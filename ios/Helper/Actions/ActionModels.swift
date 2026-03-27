import Foundation

enum ActionKind: String, Sendable, Codable, Equatable {
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

enum ActionConfirmationState: Sendable, Equatable {
    case awaitingApproval
    case dismissed
    case executing
    case completed
    case failed(String)
}

enum ActionReminderPriority: String, Sendable, Codable, CaseIterable, Equatable, Identifiable {
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

enum ActionDraft: Sendable, Equatable {
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
        let priority: ActionReminderPriority?
    }

    struct NoteDraft: Sendable, Equatable {
        let title: String
        let body: String
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

struct ProposedAction: Sendable, Equatable {
    let kind: ActionKind
    let title: String
    let explanation: String
    let draft: ActionDraft
    let confirmationState: ActionConfirmationState
    let confidence: Double
    let auditReasons: [String]

    var primaryActionTitle: String { kind.primaryActionTitle }
}

enum ActionSuggestionDecision: Sendable, Equatable {
    case proposed(ProposedAction)
    case suppressed(
        kind: ActionKind?,
        confidence: Double?,
        reasons: [String]
    )
    case noAction(reasons: [String])
}

protocol ActionSuggestionDetecting: Sendable {
    func decide(for text: String) -> ActionSuggestionDecision
}

struct ActionSuggestionPolicy: Sendable, Equatable {
    let isEnabled: Bool
    let minimumConfidence: Double
    let maximumSuggestionsPerTurn: Int

    static let cautiousChat = ActionSuggestionPolicy(
        isEnabled: true,
        minimumConfidence: 0.75,
        maximumSuggestionsPerTurn: 1
    )
}

extension ActionKind {
    nonisolated init(_ kind: ChatSuggestionKind) {
        switch kind {
        case .calendar:
            self = .calendar
        case .reminder:
            self = .reminder
        case .note:
            self = .note
        case .followUp:
            self = .followUp
        }
    }
}

extension ChatSuggestionKind {
    nonisolated init(_ kind: ActionKind) {
        switch kind {
        case .calendar:
            self = .calendar
        case .reminder:
            self = .reminder
        case .note:
            self = .note
        case .followUp:
            self = .followUp
        }
    }
}

extension ActionConfirmationState {
    nonisolated init(_ state: ChatSuggestionState) {
        switch state {
        case .visible:
            self = .awaitingApproval
        case .dismissed:
            self = .dismissed
        case .executing:
            self = .executing
        case .completed:
            self = .completed
        case .failed(let message):
            self = .failed(message)
        }
    }
}

extension ChatSuggestionState {
    nonisolated init(_ state: ActionConfirmationState) {
        switch state {
        case .awaitingApproval:
            self = .visible
        case .dismissed:
            self = .dismissed
        case .executing:
            self = .executing
        case .completed:
            self = .completed
        case .failed(let message):
            self = .failed(message)
        }
    }
}

extension ActionReminderPriority {
    nonisolated init(_ priority: ChatSuggestionReminderPriority) {
        switch priority {
        case .high:
            self = .high
        case .medium:
            self = .medium
        case .low:
            self = .low
        }
    }
}

extension ChatSuggestionReminderPriority {
    nonisolated init(_ priority: ActionReminderPriority) {
        switch priority {
        case .high:
            self = .high
        case .medium:
            self = .medium
        case .low:
            self = .low
        }
    }
}

extension ActionDraft.CalendarDraft {
    nonisolated init(_ draft: ChatSuggestionDraft.CalendarDraft) {
        self.init(
            title: draft.title,
            notes: draft.notes,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: draft.isAllDay
        )
    }
}

extension ActionDraft.ReminderDraft {
    nonisolated init(_ draft: ChatSuggestionDraft.ReminderDraft) {
        self.init(
            title: draft.title,
            dueDate: draft.dueDate,
            notes: draft.notes,
            location: draft.location,
            priority: draft.priority.map(ActionReminderPriority.init)
        )
    }
}

extension ActionDraft.NoteDraft {
    nonisolated init(_ draft: ChatSuggestionDraft.NoteDraft) {
        self.init(
            title: draft.title,
            body: draft.body
        )
    }
}

extension ActionDraft.FollowUpDraft {
    nonisolated init(_ draft: ChatSuggestionDraft.FollowUpDraft) {
        self.init(
            title: draft.title,
            draftText: draft.draftText,
            contextText: draft.contextText,
            waitingSince: draft.waitingSince,
            eligibleAt: draft.eligibleAt,
            dueAt: draft.dueAt,
            clusterID: draft.clusterID
        )
    }
}

extension ActionDraft {
    nonisolated init(_ draft: ChatSuggestionDraft) {
        switch draft {
        case .calendar(let draft):
            self = .calendar(ActionDraft.CalendarDraft(draft))
        case .reminder(let draft):
            self = .reminder(ActionDraft.ReminderDraft(draft))
        case .note(let draft):
            self = .note(ActionDraft.NoteDraft(draft))
        case .followUp(let draft):
            self = .followUp(ActionDraft.FollowUpDraft(draft))
        }
    }
}

extension ChatSuggestionDraft.CalendarDraft {
    nonisolated init(_ draft: ActionDraft.CalendarDraft) {
        self.init(
            title: draft.title,
            notes: draft.notes,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: draft.isAllDay
        )
    }
}

extension ChatSuggestionDraft.ReminderDraft {
    nonisolated init(_ draft: ActionDraft.ReminderDraft) {
        self.init(
            title: draft.title,
            dueDate: draft.dueDate,
            notes: draft.notes,
            location: draft.location,
            priority: draft.priority.map(ChatSuggestionReminderPriority.init)
        )
    }
}

extension ChatSuggestionDraft.NoteDraft {
    nonisolated init(_ draft: ActionDraft.NoteDraft) {
        self.init(
            title: draft.title,
            body: draft.body
        )
    }
}

extension ChatSuggestionDraft.FollowUpDraft {
    nonisolated init(_ draft: ActionDraft.FollowUpDraft) {
        self.init(
            title: draft.title,
            draftText: draft.draftText,
            contextText: draft.contextText,
            waitingSince: draft.waitingSince,
            eligibleAt: draft.eligibleAt,
            dueAt: draft.dueAt,
            clusterID: draft.clusterID
        )
    }
}

extension ChatSuggestionDraft {
    nonisolated init(_ draft: ActionDraft) {
        switch draft {
        case .calendar(let draft):
            self = .calendar(ChatSuggestionDraft.CalendarDraft(draft))
        case .reminder(let draft):
            self = .reminder(ChatSuggestionDraft.ReminderDraft(draft))
        case .note(let draft):
            self = .note(ChatSuggestionDraft.NoteDraft(draft))
        case .followUp(let draft):
            self = .followUp(ChatSuggestionDraft.FollowUpDraft(draft))
        }
    }
}

extension ProposedAction {
    nonisolated init(_ suggestion: ChatSuggestionCard) {
        self.init(
            kind: ActionKind(suggestion.kind),
            title: suggestion.title,
            explanation: suggestion.explanation,
            draft: ActionDraft(suggestion.draft),
            confirmationState: ActionConfirmationState(suggestion.state),
            confidence: suggestion.confidence,
            auditReasons: suggestion.auditReasons
        )
    }
}

extension ChatSuggestionCard {
    nonisolated init(_ action: ProposedAction) {
        self.init(
            kind: ChatSuggestionKind(action.kind),
            title: action.title,
            explanation: action.explanation,
            draft: ChatSuggestionDraft(action.draft),
            state: ChatSuggestionState(action.confirmationState),
            confidence: action.confidence,
            auditReasons: action.auditReasons
        )
    }

    nonisolated var proposedAction: ProposedAction {
        ProposedAction(self)
    }
}

extension ActionSuggestionDecision {
    nonisolated var chatSuggestionDecision: ChatSuggestionDecision {
        switch self {
        case .proposed(let action):
            return .suggestion(ChatSuggestionCard(action))
        case .suppressed(let kind, let confidence, let reasons):
            return .suppressed(
                kind: kind.map(ChatSuggestionKind.init),
                confidence: confidence,
                reasons: reasons
            )
        case .noAction(let reasons):
            return .noAction(reasons: reasons)
        }
    }
}

extension ChatSuggestionDecision {
    nonisolated init(_ decision: ActionSuggestionDecision) {
        self = decision.chatSuggestionDecision
    }
}

extension ActionSuggestionPolicy {
    nonisolated init(_ policy: ChatSuggestionPolicy) {
        self.init(
            isEnabled: policy.isEnabled,
            minimumConfidence: policy.minimumConfidence,
            maximumSuggestionsPerTurn: policy.maximumSuggestionsPerTurn
        )
    }
}

extension ChatSuggestionPolicy {
    nonisolated init(_ policy: ActionSuggestionPolicy) {
        self.init(
            isEnabled: policy.isEnabled,
            minimumConfidence: policy.minimumConfidence,
            maximumSuggestionsPerTurn: policy.maximumSuggestionsPerTurn
        )
    }
}
