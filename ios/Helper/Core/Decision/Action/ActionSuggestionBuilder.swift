import Foundation

final class ActionSuggestionBuilder {

    func buildSuggestion(
        from content: ContentObject,
        intent: IntentType,
        dateHint: Date? = nil,
        hasCalendarConflict: Bool = false,
        clusterContext: ClusterContext? = nil,
        confidence: Double? = nil
    ) -> ActionSuggestion? {

        // 1️⃣ Inaktiva kluster → inget förslag
        if let cluster = clusterContext, !cluster.isActive {
            return nil
        }

        // 2️⃣ Spamskydd: föreslå inte uppföljning igen
        if let cluster = clusterContext,
           intent == .followUp,
           cluster.followUpSuggested {
            return nil
        }

        // 3️⃣ Stora kluster → valfritt: höj tröskel
        if let cluster = clusterContext, cluster.itemCount > 5 {
            // T.ex. kräva starkare signal
        }

        // 4️⃣ Bygg upp förslag baserat på intent
        switch intent {
        case .calendar:
            return ActionSuggestion(
                type: .calendar,
                title: "Lägg till i kalender",
                explanation: calendarExplanation(
                    content: content,
                    dateHint: dateHint,
                    hasConflict: hasCalendarConflict,
                    clusterContext: clusterContext
                ),
                suggestedDate: dateHint,
                confidence: confidence,
                contentId: content.id,
                clusterId: clusterContext?.clusterId
            )

        case .reminder:
            return ActionSuggestion(
                type: .reminder,
                title: "Skapa påminnelse",
                explanation: reminderExplanation(content: content, clusterContext: clusterContext),
                suggestedDate: dateHint,
                confidence: confidence,
                contentId: content.id,
                clusterId: clusterContext?.clusterId
            )

        case .note:
            return ActionSuggestion(
                type: .note,
                title: "Spara minne",
                explanation: noteExplanation(content: content, clusterContext: clusterContext),
                confidence: confidence,
                contentId: content.id,
                clusterId: clusterContext?.clusterId
            )

        case .sendMessage:
            return ActionSuggestion(
                type: .sendMessage,
                title: "Svara?",
                explanation: sendMessageExplanation(content: content, clusterContext: clusterContext),
                confidence: confidence,
                contentId: content.id,
                clusterId: clusterContext?.clusterId
            )

        case .followUp:
            return ActionSuggestion(
                type: .followUp,
                title: "Följ upp?",
                explanation: followUpExplanation(clusterContext: clusterContext),
                confidence: confidence,
                contentId: content.id,
                clusterId: clusterContext?.clusterId
            )

        case .none:
            return ActionSuggestion(
                type: .ignore,
                title: "Ignorera",
                explanation: "Vill du ignorera detta?",
                confidence: confidence,
                contentId: content.id,
                clusterId: clusterContext?.clusterId
            )
        }
    }

    // MARK: - Förklaringar

    private func calendarExplanation(
        content: ContentObject,
        dateHint: Date?,
        hasConflict: Bool,
        clusterContext: ClusterContext? = nil
    ) -> String {
        var base: String

        if hasConflict {
            base = "Detta verkar vara ett möte som krockar i din kalender. Vill du justera?"
        } else if let date = dateHint {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(for: date, relativeTo: Date())
            base = "Du har inget planerat \(relative). Vill du lägga in detta i kalendern?"
        } else {
            base = "Detta låter som ett möte. Vill du lägga in det i kalendern?"
        }

        if let cluster = clusterContext {
            base += "\nTema: “\(cluster.title ?? "Utan namn")”."
        }

        return base
    }

    private func reminderExplanation(
        content: ContentObject,
        clusterContext: ClusterContext? = nil
    ) -> String {
        var text = "Detta verkar vara något du vill komma ihåg. Vill du skapa en påminnelse?"
        if let cluster = clusterContext {
            text += "\nTema: “\(cluster.title ?? "Utan namn")”."
        }
        return text
    }

    private func noteExplanation(
        content: ContentObject,
        clusterContext: ClusterContext? = nil
    ) -> String {
        if let cluster = clusterContext {
            return "Vill du spara detta som ett minne i temat “\(cluster.title ?? "utan namn")”?"
        } else {
            return "Vill du spara detta som ett minne?"
        }
    }

    private func sendMessageExplanation(
        content: ContentObject,
        clusterContext: ClusterContext? = nil
    ) -> String {
        if let cluster = clusterContext {
            return "Vill du svara eller följa upp inom temat “\(cluster.title ?? "utan namn")”?"
        } else {
            return "Vill du skicka ett meddelande baserat på detta innehåll?"
        }
    }

    private func followUpExplanation(
        clusterContext: ClusterContext?
    ) -> String {
        if let cluster = clusterContext {
            return "Du har inte fått svar än i temat “\(cluster.title ?? "utan namn")”. Vill du följa upp?"
        } else {
            return "Du har inte fått svar än. Vill du följa upp?"
        }
    }
}
