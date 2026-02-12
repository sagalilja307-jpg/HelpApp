import Foundation
import SwiftData
#if canImport(EventKit)
import EventKit
#endif

// ===============================================================
// File: Helper/Core/Query/QueryDataFetcher.swift
// ===============================================================

struct QueryDataFetcher: Sendable {

    func fetch(for interpretation: QueryInterpretation) async throws -> QueryResult {

        let intent = interpretation.intent
        let sources = interpretation.requiredSources   // ✅ RÄTT
        let timeRange = interpretation.timeRange

        var entries: [QueryResult.Entry] = []

        for source in sources {
            switch source {

            case .memory:
                entries += try await fetchMemory(
                    intent: intent,
                    timeRange: timeRange
                )

            case .calendar:
                entries += try await fetchCalendar(
                    intent: intent,
                    timeRange: timeRange
                )

            case .reminders:
                entries += try await fetchReminders(
                    intent: intent,
                    timeRange: timeRange
                )

            case .rawEvents:
                entries += [
                    placeholderEntry(
                        for: source,
                        intent: intent,
                        timeRange: timeRange
                    )
                ]
            }
        }

        return QueryResult(
            timeRange: timeRange,
            entries: entries,
            answer: nil
        )
    }

    // MARK: - Source-specific pipelines

    private func fetchMemory(
        intent: QueryIntent,
        timeRange: DateInterval?
    ) async throws -> [QueryResult.Entry] {
        // TODO: Integrera SwiftData / MemoryService
        return [
            placeholderEntry(
                for: .memory,
                intent: intent,
                timeRange: timeRange
            )
        ]
    }

    private func fetchCalendar(
        intent: QueryIntent,
        timeRange: DateInterval?
    ) async throws -> [QueryResult.Entry] {

        #if canImport(EventKit)
        // TODO: Integrera EventKit (EKEventStore)
        return [
            placeholderEntry(
                for: .calendar,
                intent: intent,
                timeRange: timeRange
            )
        ]
        #else
        return []
        #endif
    }

    private func fetchReminders(
        intent: QueryIntent,
        timeRange: DateInterval?
    ) async throws -> [QueryResult.Entry] {

        #if canImport(EventKit)
        // TODO: Integrera EKReminder
        return [
            placeholderEntry(
                for: .reminders,
                intent: intent,
                timeRange: timeRange
            )
        ]
        #else
        return []
        #endif
    }

    // MARK: - Placeholder

    private func placeholderEntry(
        for source: QuerySource,
        intent: QueryIntent,
        timeRange: DateInterval?
    ) -> QueryResult.Entry {

        QueryResult.Entry(
            id: UUID(),
            source: source,
            title: "Placeholder för \(source.rawValue)",
            body: "Här ska riktiga data hämtas utifrån intent \(intent.rawValue).",
            date: Date()
        )
    }
}
