import Foundation

@MainActor
protocol ChatSuggestionLogging {
    func log(
        action: DecisionAction,
        messageID: String,
        kind: ChatSuggestionKind?,
        confidence: Double?,
        reasons: [String]
    )
}

@MainActor
struct NoopChatSuggestionLogger: ChatSuggestionLogging {
    func log(
        action: DecisionAction,
        messageID: String,
        kind: ChatSuggestionKind?,
        confidence: Double?,
        reasons: [String]
    ) {
        _ = (action, messageID, kind, confidence, reasons)
    }
}

@MainActor
final class ChatSuggestionLogger: ChatSuggestionLogging {
    private let memoryService: MemoryService

    init(memoryService: MemoryService) {
        self.memoryService = memoryService
    }

    func log(
        action: DecisionAction,
        messageID: String,
        kind: ChatSuggestionKind?,
        confidence: Double?,
        reasons: [String]
    ) {
        let decisionID = "\(messageID):\(action.rawValue)"
        var payloadReasons = reasons
        payloadReasons.append("decision:\(action.rawValue)")
        if let kind {
            payloadReasons.append("kind:\(kind.rawValue)")
        }
        if let confidence {
            payloadReasons.append("confidence:\(String(format: "%.2f", confidence))")
        }

        do {
            let context = memoryService.context()
            try memoryService.appendDecision(
                actor: .system,
                decisionId: decisionID,
                action: action,
                reason: payloadReasons,
                usedMemory: [
                    "message_id": AnyCodable(messageID),
                    "decision_id": AnyCodable(decisionID),
                    "kind": AnyCodable(kind?.rawValue ?? ""),
                    "confidence": AnyCodable(confidence ?? 0),
                ],
                in: context
            )
        } catch {
            // Logging must never affect the chat experience.
        }
    }
}
