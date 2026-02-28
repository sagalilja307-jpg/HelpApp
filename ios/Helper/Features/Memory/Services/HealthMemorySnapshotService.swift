import Foundation

#if canImport(HealthKit)
@preconcurrency import HealthKit
#endif

struct HealthMemoryDaySnapshot: Sendable, Equatable {
    let date: Date
    let steps: Int?
    let exerciseMinutes: Double?
    let sleepDuration: TimeInterval?
    let mindfulDuration: TimeInterval?
    let workoutCount: Int?
    let heartRateAverage: Double?
    let restingHeartRateAverage: Double?
    let hrvAverage: Double?
    let respiratoryRateAverage: Double?
    let bloodOxygenAveragePercent: Double?
    let stateOfMindCount: Int?

    var hasAnyData: Bool {
        steps != nil
            || exerciseMinutes != nil
            || sleepDuration != nil
            || mindfulDuration != nil
            || workoutCount != nil
            || heartRateAverage != nil
            || restingHeartRateAverage != nil
            || hrvAverage != nil
            || respiratoryRateAverage != nil
            || bloodOxygenAveragePercent != nil
            || stateOfMindCount != nil
    }

    var overviewLine: String {
        var parts: [String] = []

        if let steps {
            parts.append("\(formattedInt(steps)) steg")
        }
        if let sleepDuration {
            parts.append("sömn \(formattedDuration(sleepDuration))")
        }
        if let workoutCount, workoutCount > 0 {
            parts.append("\(workoutCount) pass")
        }

        if parts.isEmpty {
            return "Ingen hälsodata ännu"
        }
        return parts.joined(separator: " · ")
    }

    var detailLines: [String] {
        var lines: [String] = []

        if let steps {
            lines.append("Steg: \(formattedInt(steps))")
        }
        if let exerciseMinutes {
            lines.append("Träningstid: \(formattedDouble(exerciseMinutes, fractionDigits: 0)) min")
        }
        if let sleepDuration {
            lines.append("Sömn: \(formattedDuration(sleepDuration))")
        }
        if let workoutCount {
            lines.append("Träningspass: \(workoutCount)")
        }
        if let mindfulDuration {
            lines.append("Mindful: \(formattedDuration(mindfulDuration))")
        }
        if let heartRateAverage {
            lines.append("Puls (snitt): \(formattedDouble(heartRateAverage, fractionDigits: 0)) slag/min")
        }
        if let restingHeartRateAverage {
            lines.append("Vilopuls (snitt): \(formattedDouble(restingHeartRateAverage, fractionDigits: 0)) slag/min")
        }
        if let hrvAverage {
            lines.append("HRV (snitt): \(formattedDouble(hrvAverage, fractionDigits: 0)) ms")
        }
        if let respiratoryRateAverage {
            lines.append("Andning (snitt): \(formattedDouble(respiratoryRateAverage, fractionDigits: 1)) andetag/min")
        }
        if let bloodOxygenAveragePercent {
            lines.append("Blodsyre (snitt): \(formattedDouble(bloodOxygenAveragePercent, fractionDigits: 1))%")
        }
        if let stateOfMindCount {
            lines.append("Sinnestillstånd: \(stateOfMindCount) registreringar")
        }

        if lines.isEmpty {
            lines.append("Ingen hälsodata för dagen ännu.")
        }

        return lines
    }

    private func formattedInt(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formattedDouble(_ value: Double, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = fractionDigits
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(fractionDigits)f", value)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60.0).rounded())
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours > 0 {
            return "\(hours) h \(remainder) min"
        }
        return "\(remainder) min"
    }
}

final class HealthMemorySnapshotService {
    static let shared = HealthMemorySnapshotService()

#if canImport(HealthKit)
    private let healthStore = HKHealthStore()
#endif

    private init() {}

    func fetchSnapshot(for date: Date, calendar: Calendar = .current) async -> HealthMemoryDaySnapshot {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return emptySnapshot(for: dayStart)
        }

        async let steps = cumulativeQuantity(
            .stepCount,
            unit: .count(),
            start: dayStart,
            end: dayEnd
        ).map { Int($0.rounded()) }

        async let exerciseMinutes = cumulativeQuantity(
            .appleExerciseTime,
            unit: .minute(),
            start: dayStart,
            end: dayEnd
        )

        async let sleepDuration = categoryDuration(
            .sleepAnalysis,
            start: dayStart,
            end: dayEnd
        )

        async let mindfulDuration = categoryDuration(
            .mindfulSession,
            start: dayStart,
            end: dayEnd
        )

        async let workoutCount = sampleCount(
            sampleType: HKWorkoutType.workoutType(),
            start: dayStart,
            end: dayEnd
        )

        async let heartRateAverage = averageQuantity(
            .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: dayStart,
            end: dayEnd
        )

        async let restingHeartRateAverage = averageQuantity(
            .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: dayStart,
            end: dayEnd
        )

        async let hrvAverage = averageQuantity(
            .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            start: dayStart,
            end: dayEnd
        )

        async let respiratoryRateAverage = averageQuantity(
            .respiratoryRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: dayStart,
            end: dayEnd
        )

        async let bloodOxygenAveragePercent = averageQuantity(
            .oxygenSaturation,
            unit: .percent(),
            start: dayStart,
            end: dayEnd
        ).map { $0 * 100 }

        async let stateOfMindCount = stateOfMindSampleCount(start: dayStart, end: dayEnd)

        return await HealthMemoryDaySnapshot(
            date: dayStart,
            steps: steps,
            exerciseMinutes: exerciseMinutes,
            sleepDuration: sleepDuration,
            mindfulDuration: mindfulDuration,
            workoutCount: workoutCount,
            heartRateAverage: heartRateAverage,
            restingHeartRateAverage: restingHeartRateAverage,
            hrvAverage: hrvAverage,
            respiratoryRateAverage: respiratoryRateAverage,
            bloodOxygenAveragePercent: bloodOxygenAveragePercent,
            stateOfMindCount: stateOfMindCount
        )
#else
        return emptySnapshot(for: dayStart)
#endif
    }

    private func emptySnapshot(for date: Date) -> HealthMemoryDaySnapshot {
        HealthMemoryDaySnapshot(
            date: date,
            steps: nil,
            exerciseMinutes: nil,
            sleepDuration: nil,
            mindfulDuration: nil,
            workoutCount: nil,
            heartRateAverage: nil,
            restingHeartRateAverage: nil,
            hrvAverage: nil,
            respiratoryRateAverage: nil,
            bloodOxygenAveragePercent: nil,
            stateOfMindCount: nil
        )
    }
}

#if canImport(HealthKit)
private extension HealthMemorySnapshotService {
    func predicate(start: Date, end: Date) -> NSPredicate {
        HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate, .strictEndDate]
        )
    }

    func cumulativeQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate(start: start, end: end),
                options: .cumulativeSum
            ) { _, result, _ in
                let value = result?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    func averageQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate(start: start, end: end),
                options: .discreteAverage
            ) { _, result, _ in
                let value = result?.averageQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    func categoryDuration(
        _ identifier: HKCategoryTypeIdentifier,
        start: Date,
        end: Date
    ) async -> TimeInterval? {
        guard let type = HKObjectType.categoryType(forIdentifier: identifier) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate(start: start, end: end),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let categorySamples = (samples as? [HKCategorySample]) ?? []
                let total = categorySamples.reduce(0.0) { partial, sample in
                    partial + sample.endDate.timeIntervalSince(sample.startDate)
                }
                continuation.resume(returning: total > 0 ? total : nil)
            }
            healthStore.execute(query)
        }
    }

    func sampleCount(
        sampleType: HKSampleType,
        start: Date,
        end: Date
    ) async -> Int? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate(start: start, end: end),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.count)
            }
            healthStore.execute(query)
        }
    }

    func stateOfMindSampleCount(start: Date, end: Date) async -> Int? {
        if #available(iOS 17.0, *) {
            return await sampleCount(sampleType: HKObjectType.stateOfMindType(), start: start, end: end)
        }
        return nil
    }
}
#endif
