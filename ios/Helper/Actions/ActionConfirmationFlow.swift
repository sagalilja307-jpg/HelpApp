import Foundation

enum ActionConfirmationEvent: Sendable, Equatable {
    case dismiss
    case beginExecution
    case restoreApproval
    case complete
    case fail(String)
}

enum ActionConfirmationFlow {
    static func transition(
        from state: ActionConfirmationState,
        event: ActionConfirmationEvent
    ) -> ActionConfirmationState {
        switch event {
        case .dismiss:
            guard !isTerminal(state) else { return state }
            return .dismissed
        case .beginExecution:
            guard !isTerminal(state) else { return state }
            return .executing
        case .restoreApproval:
            switch state {
            case .completed, .dismissed:
                return state
            case .awaitingApproval, .executing, .failed:
                return .awaitingApproval
            }
        case .complete:
            guard !isTerminal(state) else { return state }
            return .completed
        case .fail(let message):
            guard !isTerminal(state) else { return state }
            return .failed(message)
        }
    }

    private static func isTerminal(_ state: ActionConfirmationState) -> Bool {
        switch state {
        case .dismissed, .completed:
            return true
        case .awaitingApproval, .executing, .failed:
            return false
        }
    }
}
