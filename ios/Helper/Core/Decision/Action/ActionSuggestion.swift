import Foundation

/// En föreslagen åtgärd att visa för användaren.
/// Detta är alltid ett förslag – aldrig ett automatiskt beslut.
struct ActionSuggestion: Identifiable, Equatable {

    /// Unik identifierare för denna suggestion
    let id: UUID

    /// Typ av åtgärd som föreslås (t.ex. kalender, påminnelse, meddelande)
    let type: ActionType

    /// Kort titel för visning i UI (t.ex. knapptext eller rubrik)
    let title: String?

    /// Förklaring i naturligt språk som visas för användaren
    let explanation: String

    /// Eventuellt datum som förslaget baseras på
    let suggestedDate: Date?

    /// Osäkerhetsmått från exempelvis LLM, mellan 0.0–1.0
    let confidence: Double?

    /// ID för innehållet som förslaget kommer från
    let contentId: UUID

    /// (Valfritt) ID för tillhörande kluster om det är relevant
    let clusterId: String?

    /// Initiera en ny ActionSuggestion
    init(
        type: ActionType,
        title: String? = nil,
        explanation: String,
        suggestedDate: Date? = nil,
        confidence: Double? = nil,
        contentId: UUID,
        clusterId: String? = nil
    ) {
        self.id = UUID()
        self.type = type
        self.title = title
        self.explanation = explanation
        self.suggestedDate = suggestedDate
        self.confidence = confidence
        self.contentId = contentId
        self.clusterId = clusterId
    }
}
