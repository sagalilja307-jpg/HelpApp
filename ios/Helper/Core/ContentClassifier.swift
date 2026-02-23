// ContentClassifier.swift


import Foundation

final class ContentClassifier {

    // MARK: - Public API

    func classify(_ content: ContentObject) -> IntentType {
        let text = normalize(content.rawText)

        // Viktigast först
        if looksLikeOutgoingMessage(text) {
            return .sendMessage
        }

        if looksLikeCalendarEvent(text) {
            return .calendar
        }

        if looksLikeReminder(text) {
            return .reminder
        }

        if looksLikeSavableInfo(text) {
            return .note
        }

        return .none
    }
}

private extension ContentClassifier {

    func normalize(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func looksLikeCalendarEvent(_ text: String) -> Bool {
        let calendarKeywords = [
            "ses",
            "träffas",
            "möte",
            "middag",
            "lunch",
            "kl ",
            "klockan",
            "på ",
            "imorgon",
            "på fredag",
            "på måndag",
            "den ",
            "datum"
        ]
        return calendarKeywords.contains { text.contains($0) }
    }

    func looksLikeReminder(_ text: String) -> Bool {
        let reminderKeywords = [
            "kom ihåg",
            "glöm inte",
            "kan du",
            "behöver",
            "måste",
            "ska jag",
            "ring",
            "hämta",
            "svara",
            "skicka"
        ]
        return reminderKeywords.contains { text.contains($0) }
    }

    func looksLikeSavableInfo(_ text: String) -> Bool {
        let infoIndicators = [
            "kod",
            "lösenord",
            "referens",
            "bokning",
            "biljett",
            "adress",
            "instruktion",
            "info",
            "nummer"
        ]
        return infoIndicators.contains { text.contains($0) }
    }

    func looksLikeOutgoingMessage(_ text: String) -> Bool {
        let messageIndicators = [
            "jag hör av mig",
            "jag skriver",
            "skriver till",
            "mejlar",
            "mailar",
            "jag skickar",
            "jag svarar",
            "skickar ett meddelande"
        ]
        return messageIndicators.contains { text.contains($0) }
    }
}

