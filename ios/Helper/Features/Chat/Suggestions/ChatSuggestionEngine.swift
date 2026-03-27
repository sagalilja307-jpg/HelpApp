import Foundation

struct ChatSuggestionEngine: ChatSuggestionEvaluating {
    private let detector: any ActionSuggestionDetecting

    init(
        policy: ChatSuggestionPolicy = .cautiousChat,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.detector = HeuristicActionSuggestionDetector(
            policy: ActionSuggestionPolicy(policy),
            nowProvider: nowProvider,
            calendar: calendar
        )
    }

    init(actionSuggestionDetector: any ActionSuggestionDetecting) {
        self.detector = actionSuggestionDetector
    }

    func decide(for text: String) -> ChatSuggestionDecision {
        detector.decide(for: text).chatSuggestionDecision
    }
}
