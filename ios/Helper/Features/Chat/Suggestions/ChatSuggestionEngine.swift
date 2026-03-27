import Foundation

struct ChatSuggestionEngine: ChatSuggestionEvaluating {
    private struct ResolvedDateHint: Sendable, Equatable {
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool
        let reasons: [String]
    }

    private let policy: ChatSuggestionPolicy
    private let nowProvider: @Sendable () -> Date
    private let calendar: Calendar
    private let followUpSchedulePolicy: FollowUpSchedulePolicy

    init(
        policy: ChatSuggestionPolicy = .cautiousChat,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.policy = policy
        self.nowProvider = nowProvider
        self.calendar = calendar
        self.followUpSchedulePolicy = FollowUpSchedulePolicy(calendar: calendar)
    }

    func decide(for text: String) -> ChatSuggestionDecision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .noAction(reasons: ["trigger:user_text", "reason:empty_input"])
        }

        if !policy.isEnabled {
            return .suppressed(
                kind: nil,
                confidence: nil,
                reasons: ["trigger:user_text", "reason:suggestions_disabled"]
            )
        }

        if policy.maximumSuggestionsPerTurn <= 0 {
            return .suppressed(
                kind: nil,
                confidence: nil,
                reasons: ["trigger:user_text", "reason:max_suggestions_reached"]
            )
        }

        if let createCandidate = calendarCreationCandidate(from: trimmed) {
            if createCandidate.confidence < policy.minimumConfidence {
                return .suppressed(
                    kind: createCandidate.kind,
                    confidence: createCandidate.confidence,
                    reasons: createCandidate.auditReasons + ["reason:below_confidence_threshold"]
                )
            }
            return .suggestion(createCandidate)
        }

        if let followUpCandidate = followUpCandidate(from: trimmed) {
            if followUpCandidate.confidence < policy.minimumConfidence {
                return .suppressed(
                    kind: followUpCandidate.kind,
                    confidence: followUpCandidate.confidence,
                    reasons: followUpCandidate.auditReasons + ["reason:below_confidence_threshold"]
                )
            }
            return .suggestion(followUpCandidate)
        }

        if isDataQueryLike(trimmed) {
            return .noAction(reasons: ["trigger:user_text", "reason:data_query_like"])
        }

        let candidate = calendarCandidate(from: trimmed)
            ?? reminderCandidate(from: trimmed)
            ?? noteCandidate(from: trimmed)

        guard let candidate else {
            return .noAction(reasons: ["trigger:user_text", "reason:no_matching_heuristic"])
        }

        if candidate.confidence < policy.minimumConfidence {
            return .suppressed(
                kind: candidate.kind,
                confidence: candidate.confidence,
                reasons: candidate.auditReasons + ["reason:below_confidence_threshold"]
            )
        }

        return .suggestion(candidate)
    }
}

private extension ChatSuggestionEngine {
    func calendarCreationCandidate(from text: String) -> ChatSuggestionCard? {
        let normalized = normalize(text)
        let creationSignals = [
            "lägg in", "lagg in", "lägga in", "lagga in",
            "lägg till", "lagg till", "lägga till", "lagga till",
            "boka in", "skapa event", "skapa ett event",
            "sätt in", "satt in", "sätta in", "satta in"
        ]
        let matchedSignals = creationSignals.filter { normalized.contains($0) }
        let hasCalendarTarget = normalized.contains("i kalendern")
        let hasBookingVerb = normalized.contains("boka ")
            || normalized.hasPrefix("boka ")
            || normalized.contains("boka möte")
            || normalized.contains("boka mote")
        let hasPlanningStatement = normalized.hasPrefix("jag ska ")
            || normalized.contains(" jag ska ")
            || normalized.hasPrefix("jag behöver ")
            || normalized.contains(" jag behöver ")
            || normalized.hasPrefix("jag måste ")
            || normalized.contains(" jag måste ")

        guard !matchedSignals.isEmpty || hasBookingVerb else {
            return nil
        }

        guard hasCalendarTarget || hasPlanningStatement || hasBookingVerb else {
            return nil
        }

        guard let resolvedDate = resolveDateHint(in: text, requireDate: true) else {
            return nil
        }

        let cleanedTitle = calendarCreationTitle(from: text)
        let title = cleanedTitle.isEmpty ? "Ny händelse" : cleanedTitle
        let notes = title.caseInsensitiveCompare(text.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame ? "" : text
        let hasExplicitTime = resolvedDate.reasons.contains("date:explicit_time")
        let confidence = hasExplicitTime ? 0.96 : 0.88

        return ChatSuggestionCard(
            kind: .calendar,
            title: "Det här ser ut som något att lägga i kalendern",
            explanation: "Vill du öppna ett kalenderutkast med det här förifyllt?",
            draft: .calendar(
                .init(
                    title: title,
                    notes: notes,
                    startDate: resolvedDate.startDate,
                    endDate: resolvedDate.endDate,
                    isAllDay: resolvedDate.isAllDay
                )
            ),
            state: .visible,
            confidence: confidence,
            auditReasons: [
                "trigger:user_text",
                "action_kind:calendar",
                "intent:create_request"
            ] + matchedSignals.map { "keyword:\($0)" } + resolvedDate.reasons
        )
    }

    func calendarCandidate(from text: String) -> ChatSuggestionCard? {
        let normalized = normalize(text)
        let eventKeywords = [
            "möte", "möten", "träff", "träffas", "ses", "middag", "lunch", "frukost",
            "fika", "intervju", "avstämning", "samtal", "middag med", "lunch med"
        ]
        let matchedKeywords = eventKeywords.filter { normalized.contains(normalize($0)) }
        guard !matchedKeywords.isEmpty else {
            return nil
        }

        guard let resolvedDate = resolveDateHint(in: text, requireDate: true) else {
            return nil
        }

        let cleanedTitle = stripTemporalTokens(from: text)
        let title = cleanedTitle.isEmpty ? "Ny händelse" : cleanedTitle
        let notes = title.caseInsensitiveCompare(text) == .orderedSame ? "" : text
        let hasExplicitTime = resolvedDate.reasons.contains("date:explicit_time")
        let confidence = hasExplicitTime ? 0.94 : 0.86

        return ChatSuggestionCard(
            kind: .calendar,
            title: "Det här ser ut som en plan med tid",
            explanation: "Vill du öppna ett kalenderutkast med det här förifyllt?",
            draft: .calendar(
                .init(
                    title: title,
                    notes: notes,
                    startDate: resolvedDate.startDate,
                    endDate: resolvedDate.endDate,
                    isAllDay: resolvedDate.isAllDay
                )
            ),
            state: .visible,
            confidence: confidence,
            auditReasons: [
                "trigger:user_text",
                "action_kind:calendar",
                "heuristic:calendar_keywords",
            ] + matchedKeywords.map { "keyword:\($0)" } + resolvedDate.reasons
        )
    }

    func reminderCandidate(from text: String) -> ChatSuggestionCard? {
        let normalized = normalize(text)

        let strongSignals = [
            "kom ihåg", "kom ihag", "glöm inte", "glom inte", "påminn mig", "paminn mig",
            "påminn", "paminn", "att göra", "att gora", "todo", "to do"
        ]
        let taskVerbs = [
            "ringa", "ring", "betala", "hämta", "hamta", "köp", "kop", "skicka",
            "maila", "mejla", "svara", "boka", "fixa"
        ]

        let matchedStrongSignals = strongSignals.filter { normalized.contains($0) }
        let matchedTaskVerbs = taskVerbs.filter { normalized.contains($0) }
        let hasMediumSignal = matchedTaskVerbs.isEmpty == false && (
            normalized.contains("måste")
            || normalized.contains("maste")
            || normalized.contains("behöver")
            || normalized.contains("behover")
            || normalized.contains("ska ")
        )

        guard !matchedStrongSignals.isEmpty || hasMediumSignal else {
            return nil
        }

        let dueDate = resolveDateHint(in: text, requireDate: false)
        let title = suggestionTitle(
            from: stripReminderLeadAndTemporalTokens(from: text),
            fallback: "Ny påminnelse"
        )
        let location = extractLocationHint(from: text)
        let priority = extractReminderPriority(from: normalized)
        let confidence = matchedStrongSignals.isEmpty ? 0.79 : 0.9

        var auditReasons = [
            "trigger:user_text",
            "action_kind:reminder",
        ]
        if matchedStrongSignals.isEmpty == false {
            auditReasons.append("heuristic:reminder_signal")
            auditReasons.append(contentsOf: matchedStrongSignals.map { "keyword:\($0)" })
        } else {
            auditReasons.append("heuristic:task_signal")
            auditReasons.append(contentsOf: matchedTaskVerbs.map { "keyword:\($0)" })
        }
        if let dueDate {
            auditReasons.append(contentsOf: dueDate.reasons)
        }
        if priority != nil {
            auditReasons.append("heuristic:priority_signal")
        }

        return ChatSuggestionCard(
            kind: .reminder,
            title: "Det här låter som något att komma ihåg",
            explanation: "Vill du öppna en förifylld påminnelse?",
            draft: .reminder(
                .init(
                    title: title,
                    dueDate: dueDate?.startDate,
                    notes: text,
                    location: location,
                    priority: priority
                )
            ),
            state: .visible,
            confidence: confidence,
            auditReasons: auditReasons
        )
    }

    func noteCandidate(from text: String) -> ChatSuggestionCard? {
        if text.contains("?") {
            return nil
        }

        let normalized = normalize(text)
        let noteLabels: [(token: String, title: String)] = [
            ("portkod", "Portkod"),
            ("lösenord", "Lösenord"),
            ("losenord", "Lösenord"),
            ("wifi", "WiFi"),
            ("wi-fi", "WiFi"),
            ("adress", "Adress"),
            ("bokning", "Bokning"),
            ("biljett", "Biljett"),
            ("referens", "Referens"),
            ("instruktion", "Instruktion"),
            ("kod", "Kod"),
            ("nummer", "Nummer"),
        ]

        guard let matched = noteLabels.first(where: { normalized.contains(normalize($0.token)) }) else {
            return nil
        }

        let hasStructuredValue = text.contains(":") || text.rangeOfCharacter(from: .decimalDigits) != nil
        let confidence = hasStructuredValue ? 0.88 : 0.78

        return ChatSuggestionCard(
            kind: .note,
            title: "Det här ser ut som info att spara",
            explanation: "Vill du öppna en anteckning med det här förifyllt?",
            draft: .note(
                .init(
                    title: matched.title,
                    body: text
                )
            ),
            state: .visible,
            confidence: confidence,
            auditReasons: [
                "trigger:user_text",
                "action_kind:note",
                "heuristic:reference_info",
                "keyword:\(matched.token)",
            ]
        )
    }

    func followUpCandidate(from text: String) -> ChatSuggestionCard? {
        let normalized = normalize(text)

        let explicitSignals = [
            "följ upp", "folj upp", "följa upp", "folja upp", "follow up",
            "påminn mig att följa upp", "paminn mig att folja upp",
            "kan du följa upp", "kan du folja upp"
        ]
        let outgoingSignals = [
            "skrev till", "skrivit till", "mejlade", "mailade", "hörde av mig",
            "horde av mig", "ringde", "pingade", "skickade till", "svarade"
        ]
        let waitingSignals = [
            "väntar på svar", "vantar pa svar", "om hon inte svarar",
            "om han inte svarar", "om de inte svarar", "om ingen svarar",
            "om jag inte får svar", "om jag inte far svar", "om inget svar kommer"
        ]

        let matchedExplicitSignals = explicitSignals.filter { normalized.contains($0) }
        let matchedOutgoingSignals = outgoingSignals.filter { normalized.contains($0) }
        let matchedWaitingSignals = waitingSignals.filter { normalized.contains($0) }

        let hasFollowUpIntent = !matchedExplicitSignals.isEmpty
            || (!matchedOutgoingSignals.isEmpty && !matchedWaitingSignals.isEmpty)
        guard hasFollowUpIntent else {
            return nil
        }

        let confidence: Double
        if !matchedExplicitSignals.isEmpty && (!matchedOutgoingSignals.isEmpty || !matchedWaitingSignals.isEmpty) {
            confidence = 0.94
        } else if !matchedExplicitSignals.isEmpty {
            confidence = 0.87
        } else {
            confidence = 0.81
        }

        let recipient = extractFollowUpRecipient(from: text)
        let waitingSince = nowProvider()
        let eligibleAt = followUpSchedulePolicy.eligibleAt(waitingSince: waitingSince)
        let dueAt = followUpSchedulePolicy.dueAt(waitingSince: waitingSince)
        let title = followUpTitle(for: recipient)
        let contextText = followUpContextText(for: recipient, originalText: text)
        let draftText = followUpDraftText(for: recipient)

        return ChatSuggestionCard(
            kind: .followUp,
            title: "Det här låter som något att följa upp",
            explanation: "Vill du lägga upp en uppföljning och bli påmind i morgonbitti om det fortfarande väntar?",
            draft: .followUp(
                .init(
                    title: title,
                    draftText: draftText,
                    contextText: contextText,
                    waitingSince: waitingSince,
                    eligibleAt: eligibleAt,
                    dueAt: dueAt,
                    clusterID: nil
                )
            ),
            state: .visible,
            confidence: confidence,
            auditReasons: [
                "trigger:user_text",
                "action_kind:follow_up",
                "heuristic:waiting_for_response",
                "due_policy:24h_then_next_09",
                "intent:follow_up_request"
            ]
            + matchedExplicitSignals.map { "keyword:\($0)" }
            + matchedOutgoingSignals.map { "keyword:\($0)" }
            + matchedWaitingSignals.map { "keyword:\($0)" }
        )
    }

    func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isDataQueryLike(_ text: String) -> Bool {
        let normalized = normalize(text)
        let patterns = [
            "vad ", "hur ", "när ", "nar ", "var ", "visa ", "hitta ", "sök ",
            "sok ", "har jag ", "finns det ", "vilka ", "vilket ", "vilken "
        ]
        return patterns.contains { normalized.hasPrefix($0) }
    }

    func suggestionTitle(from text: String, fallback: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return fallback }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    func stripTemporalTokens(from text: String) -> String {
        let patterns = [
            #"\b(i kväll|ikväll|idag|imorgon|i morgon|nästa vecka|nasta vecka|på måndag|pa mandag|på tisdag|pa tisdag|på onsdag|pa onsdag|på torsdag|pa torsdag|på fredag|pa fredag|på lördag|pa lordag|på söndag|pa sondag)\b"#,
            #"\bkl\.?\s*\d{1,2}(?::\d{2})?\s*(?:-|–|—|till)\s*\d{1,2}(?::\d{2})?\b"#,
            #"\bkl\.?\s*\d{1,2}(:\d{2})?\b"#,
            #"\b\d{1,2}[/-]\d{1,2}([/-]\d{2,4})?\b"#,
            #"\b\d{1,2}\s+(jan|januari|feb|februari|mar|mars|apr|april|maj|jun|juni|jul|juli|aug|augusti|sep|september|okt|oktober|nov|november|dec|december)\b"#,
        ]
        var result = text
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: " ,.-"))
        return suggestionTitle(from: result, fallback: "")
    }

    func calendarCreationTitle(from text: String) -> String {
        var result = text
        let patterns = [
            #"\b(?:kan du|skulle du kunna|vill du|hjälp mig att|hjalp mig att)\b"#,
            #"\b(?:lägga in|lagga in|lägg in|lagg in|lägga till|lagga till|lägg till|lagg till|boka in|skapa(?: ett)? event|sätta in|satta in|sätt in|satt in)\b"#,
            #"\bi kalendern\b"#,
            #"\b(?:tack|snälla|snalla)\b"#,
            #"\?$"#
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        result = result.replacingOccurrences(
            of: #"^\s*jag ska\s+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"^\s*jag behöver\s+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"^\s*jag måste\s+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        result = stripTemporalTokens(from: result)
        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: " ,.-"))
        return suggestionTitle(from: result, fallback: "")
    }

    func stripReminderLeadAndTemporalTokens(from text: String) -> String {
        var result = text.replacingOccurrences(
            of: #"^\s*(kom ihåg att|kom ihag att|glöm inte att|glom inte att|påminn mig att|paminn mig att|påminn mig|paminn mig|påminn|paminn)\s+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = stripTemporalTokens(from: result)
        return result
    }

    func extractReminderPriority(from normalizedText: String) -> ChatSuggestionReminderPriority? {
        if normalizedText.contains("viktigt")
            || normalizedText.contains("urgent")
            || normalizedText.contains("bradskande")
            || normalizedText.contains("brådskande")
            || normalizedText.contains("asap") {
            return .high
        }
        if normalizedText.contains("senare") || normalizedText.contains("när du kan") {
            return .low
        }
        return nil
    }

    func extractLocationHint(from text: String) -> String? {
        let pattern = try? NSRegularExpression(
            pattern: #"\b(?:på|pa|i)\s+([A-Za-zÅÄÖåäö0-9][A-Za-zÅÄÖåäö0-9\s-]{1,32})"#,
            options: [.caseInsensitive]
        )
        guard
            let pattern,
            let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        let value = text[range]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
        let normalized = normalize(String(value))
        if ["idag", "imorgon", "ikvall", "ikväll"].contains(normalized) {
            return nil
        }
        return value.isEmpty ? nil : String(value)
    }

    private func resolveDateHint(in text: String, requireDate: Bool) -> ResolvedDateHint? {
        let now = nowProvider()
        let normalized = normalize(text)

        var matchedDate: Date?
        var matchedReasons: [String] = []
        var isAllDay = true

        if normalized.contains("imorgon") || normalized.contains("i morgon") {
            matchedDate = calendar.date(byAdding: .day, value: 1, to: now)
            matchedReasons.append("date:relative_tomorrow")
        } else if normalized.contains("idag") {
            matchedDate = now
            matchedReasons.append("date:relative_today")
        } else if normalized.contains("ikväll") || normalized.contains("i kväll") {
            matchedDate = now
            matchedReasons.append("date:relative_tonight")
        } else if let weekdayDate = resolveWeekday(in: normalized, now: now) {
            matchedDate = weekdayDate
            matchedReasons.append("date:weekday")
        } else if let absoluteDate = resolveAbsoluteDate(in: normalized, now: now) {
            matchedDate = absoluteDate
            matchedReasons.append("date:absolute")
        }

        let explicitTimeRange = resolveTimeRange(in: normalized)
        let explicitTime = explicitTimeRange?.start ?? resolveTime(in: normalized)
        if explicitTime != nil {
            matchedReasons.append("date:explicit_time")
        }

        if requireDate && matchedDate == nil {
            return nil
        }

        let fallbackDate = explicitTime.map { _ in now }
        guard let baseDate = matchedDate ?? fallbackDate else {
            return nil
        }

        let startDate: Date
        if let explicitTime {
            isAllDay = false
            startDate = calendar.date(
                bySettingHour: explicitTime.hour,
                minute: explicitTime.minute,
                second: 0,
                of: baseDate
            ) ?? baseDate
        } else if matchedReasons.contains("date:relative_tonight") {
            isAllDay = false
            startDate = calendar.date(
                bySettingHour: 19,
                minute: 0,
                second: 0,
                of: baseDate
            ) ?? baseDate
        } else {
            startDate = calendar.startOfDay(for: baseDate)
        }

        let endDate: Date
        if let explicitTimeRange {
            isAllDay = false
            endDate = explicitTimeRange.endDate(startDate, calendar)
        } else if isAllDay {
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        } else {
            endDate = calendar.date(byAdding: .hour, value: 1, to: startDate) ?? startDate
        }

        return ResolvedDateHint(
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            reasons: matchedReasons
        )
    }

    func resolveWeekday(in normalized: String, now: Date) -> Date? {
        let weekdays: [(tokens: [String], weekday: Int)] = [
            (["måndag", "mandag"], 2),
            (["tisdag"], 3),
            (["onsdag"], 4),
            (["torsdag"], 5),
            (["fredag"], 6),
            (["lördag", "lordag"], 7),
            (["söndag", "sondag"], 1),
        ]

        guard let matchedWeekday = weekdays.first(where: { entry in
            entry.tokens.contains { token in
                normalized.contains("på \(token)") || normalized.contains("pa \(token)")
            }
        }) else {
            return nil
        }

        return calendar.nextDate(
            after: now.addingTimeInterval(-1),
            matching: DateComponents(weekday: matchedWeekday.weekday),
            matchingPolicy: .nextTime
        )
    }

    func resolveAbsoluteDate(in normalized: String, now: Date) -> Date? {
        if let slashDate = resolveSlashDate(in: normalized, now: now) {
            return slashDate
        }
        return resolveMonthDate(in: normalized, now: now)
    }

    func resolveSlashDate(in normalized: String, now: Date) -> Date? {
        guard
            let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b"#),
            let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
        else {
            return nil
        }

        let day = intFrom(match.range(at: 1), in: normalized)
        let month = intFrom(match.range(at: 2), in: normalized)
        let parsedYear = intFrom(match.range(at: 3), in: normalized)

        guard let day, let month else { return nil }
        let year: Int
        if let parsedYear {
            year = parsedYear < 100 ? parsedYear + 2000 : parsedYear
        } else {
            year = calendar.component(.year, from: now)
        }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    func resolveMonthDate(in normalized: String, now: Date) -> Date? {
        let monthTokens: [String: Int] = [
            "jan": 1, "januari": 1,
            "feb": 2, "februari": 2,
            "mar": 3, "mars": 3,
            "apr": 4, "april": 4,
            "maj": 5,
            "jun": 6, "juni": 6,
            "jul": 7, "juli": 7,
            "aug": 8, "augusti": 8,
            "sep": 9, "september": 9,
            "okt": 10, "oktober": 10,
            "nov": 11, "november": 11,
            "dec": 12, "december": 12,
        ]

        let tokenPattern = monthTokens.keys.sorted(by: >).joined(separator: "|")
        let pattern = "(\\d{1,2})\\s+(\(tokenPattern))"
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
        else {
            return nil
        }

        guard
            let day = intFrom(match.range(at: 1), in: normalized),
            let monthRange = Range(match.range(at: 2), in: normalized)
        else {
            return nil
        }

        let monthToken = String(normalized[monthRange])
        guard let month = monthTokens[monthToken] else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    func resolveTime(in normalized: String) -> (hour: Int, minute: Int)? {
        guard
            let regex = try? NSRegularExpression(pattern: #"\b(?:kl\.?\s*)?(\d{1,2})(?::(\d{2}))\b|\bkl\.?\s*(\d{1,2})\b"#, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
        else {
            return nil
        }

        if let hour = intFrom(match.range(at: 1), in: normalized) {
            let minute = intFrom(match.range(at: 2), in: normalized) ?? 0
            return (hour, minute)
        }
        if let hour = intFrom(match.range(at: 3), in: normalized) {
            return (hour, 0)
        }
        return nil
    }

    func resolveTimeRange(in normalized: String) -> (start: (hour: Int, minute: Int), endDate: (Date, Calendar) -> Date)? {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"\b(?:kl\.?\s*)?(\d{1,2})(?::(\d{2}))?\s*(?:-|–|—|till)\s*(\d{1,2})(?::(\d{2}))?\b"#,
                options: [.caseInsensitive]
            ),
            let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
            let startHour = intFrom(match.range(at: 1), in: normalized),
            let endHour = intFrom(match.range(at: 3), in: normalized)
        else {
            return nil
        }

        let startMinute = intFrom(match.range(at: 2), in: normalized) ?? 0
        let endMinute = intFrom(match.range(at: 4), in: normalized) ?? 0

        return (
            start: (startHour, startMinute),
            endDate: { startDate, calendar in
                var end = calendar.date(
                    bySettingHour: endHour,
                    minute: endMinute,
                    second: 0,
                    of: startDate
                ) ?? startDate
                if end <= startDate {
                    end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
                }
                return end
            }
        )
    }

    func intFrom(_ range: NSRange, in text: String) -> Int? {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
            return nil
        }
        return Int(text[swiftRange])
    }

    func extractFollowUpRecipient(from text: String) -> String? {
        let patterns = [
            #"(?:följ upp med|folj upp med|mejlade|mailade|ringde|pingade)\s+([A-ZÅÄÖa-zåäö][A-Za-zÅÄÖåäö-]+)"#,
            #"(?:skrev till|skrivit till|hörde av mig till|horde av mig till|skickade till)\s+([A-ZÅÄÖa-zåäö][A-Za-zÅÄÖåäö-]+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..., in: text)
            guard
                let match = regex.firstMatch(in: text, range: range),
                let recipientRange = Range(match.range(at: 1), in: text)
            else {
                continue
            }

            let value = text[recipientRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return suggestionTitle(from: value, fallback: value)
            }
        }

        return nil
    }

    func followUpTitle(for recipient: String?) -> String {
        guard let recipient, !recipient.isEmpty else {
            return "Följ upp"
        }
        return "Följ upp med \(recipient)"
    }

    func followUpContextText(for recipient: String?, originalText: String) -> String {
        guard let recipient, !recipient.isEmpty else {
            return originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Väntar på svar från \(recipient)."
    }

    func followUpDraftText(for recipient: String?) -> String {
        guard let recipient, !recipient.isEmpty else {
            return "Hej! Jag ville bara följa upp mitt tidigare meddelande."
        }
        return "Hej \(recipient)! Jag ville bara följa upp mitt tidigare meddelande. Återkom gärna när du har möjlighet."
    }
}
