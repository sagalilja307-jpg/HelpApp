import Foundation

#if canImport(HealthKit)
@preconcurrency import HealthKit
#endif

@MainActor
struct HealthQueryFetcher {
    enum Metric: String {
        case stepCount = "step_count"
        case distance
        case activeEnergy = "active_energy"
        case exerciseTime = "exercise_time"
        case workout
        case sleep
        case mindfulSession = "mindful_session"
        case stateOfMind = "state_of_mind"
        case heartRate = "heart_rate"
        case restingHeartRate = "resting_heart_rate"
        case hrv
        case respiratoryRate = "respiratory_rate"
        case bloodOxygen = "blood_oxygen"
    }

#if canImport(HealthKit)
    private let healthStore: HKHealthStore
#endif

    #if canImport(HealthKit)
    init(healthStore: HKHealthStore = HKHealthStore()) {
        #if canImport(HealthKit)
        self.healthStore = healthStore
        #endif
    }
    #else
    init() {}
    #endif

    func collect(
        for intent: BackendIntentPlanDTO,
        timeRange: DateInterval?,
        userQuery: UserQuery
    ) async throws -> LocalCollectedResult {
        _ = userQuery

#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return LocalCollectedResult(entries: [])
        }

        let metric = metric(from: intent.filters)
        let aggregation = aggregation(from: intent)
        let interval = resolvedInterval(
            timeRange: timeRange,
            timeScope: intent.timeScope
        )

        let entries: [QueryResult.Entry]
        switch metric {
        case .workout:
            entries = try await collectWorkoutEntries(
                interval: interval,
                aggregation: aggregation,
                operation: intent.operation,
                filters: intent.filters
            )
        case .sleep:
            entries = try await collectSleepEntries(
                interval: interval,
                aggregation: aggregation,
                operation: intent.operation
            )
        case .mindfulSession:
            entries = try await collectMindfulEntries(
                interval: interval,
                aggregation: aggregation,
                operation: intent.operation
            )
        case .stateOfMind:
            entries = try await collectStateOfMindEntries(
                interval: interval,
                operation: intent.operation
            )
        default:
            entries = try await collectQuantityEntries(
                metric: metric,
                interval: interval,
                aggregation: aggregation,
                operation: intent.operation
            )
        }

        return LocalCollectedResult(entries: entries)
#else
        return LocalCollectedResult(entries: [])
#endif
    }
}

#if canImport(HealthKit)
private extension HealthQueryFetcher {
    struct QuantityMetricDescriptor {
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        let title: String
    }

    func metric(from filters: [String: AnyCodable]) -> Metric {
        guard
            let raw = filters["metric"]?.value as? String,
            let metric = Metric(rawValue: raw)
        else {
            return .stepCount
        }
        return metric
    }

    func aggregation(from intent: BackendIntentPlanDTO) -> String {
        if let raw = intent.filters["aggregation"]?.value as? String, !raw.isEmpty {
            return raw.lowercased()
        }
        switch intent.operation {
        case .count, .exists:
            return "count"
        case .latest:
            return "latest"
        default:
            return "sum"
        }
    }

    func resolvedInterval(
        timeRange: DateInterval?,
        timeScope: BackendTimeScopeDTO
    ) -> DateInterval? {
        if let timeRange {
            return timeRange
        }
        if let start = timeScope.start, let end = timeScope.end {
            if start <= end {
                return DateInterval(start: start, end: end)
            }
            return DateInterval(start: end, end: start)
        }

        let now = DateService.shared.now()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        return DateInterval(start: start, end: now)
    }

    func descriptor(for metric: Metric) -> QuantityMetricDescriptor? {
        switch metric {
        case .stepCount:
            return .init(
                identifier: .stepCount,
                unit: .count(),
                title: "Steg"
            )
        case .distance:
            return .init(
                identifier: .distanceWalkingRunning,
                unit: .meterUnit(with: .kilo),
                title: "Distans"
            )
        case .activeEnergy:
            return .init(
                identifier: .activeEnergyBurned,
                unit: .kilocalorie(),
                title: "Aktiv energi"
            )
        case .exerciseTime:
            return .init(
                identifier: .appleExerciseTime,
                unit: .minute(),
                title: "Träningstid"
            )
        case .heartRate:
            return .init(
                identifier: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                title: "Puls"
            )
        case .restingHeartRate:
            return .init(
                identifier: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                title: "Vilopuls"
            )
        case .hrv:
            return .init(
                identifier: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                title: "HRV"
            )
        case .respiratoryRate:
            return .init(
                identifier: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                title: "Andningsfrekvens"
            )
        case .bloodOxygen:
            return .init(
                identifier: .oxygenSaturation,
                unit: .percent(),
                title: "Blodsyre"
            )
        case .workout, .sleep, .mindfulSession, .stateOfMind:
            return nil
        }
    }

    func collectQuantityEntries(
        metric: Metric,
        interval: DateInterval?,
        aggregation: String,
        operation: BackendIntentOperation
    ) async throws -> [QueryResult.Entry] {
        guard
            let descriptor = descriptor(for: metric),
            let quantityType = HKObjectType.quantityType(forIdentifier: descriptor.identifier)
        else {
            return []
        }

        let predicate = interval.map(samplePredicate(for:))
        if aggregation == "sum" || aggregation == "average" {
            let options: HKStatisticsOptions = aggregation == "average" ? .discreteAverage : .cumulativeSum
            let value = try await fetchStatisticsValue(
                for: quantityType,
                unit: descriptor.unit,
                options: options,
                predicate: predicate
            )
            guard let value else { return [] }

            let title = formattedAggregateTitle(
                metric: metric,
                baseTitle: descriptor.title,
                value: value,
                aggregation: aggregation
            )
            return [
                QueryResult.Entry(
                    id: UUID(),
                    source: .health,
                    title: title,
                    body: nil,
                    date: interval?.end ?? DateService.shared.now()
                )
            ]
        }

        let sampleLimit = operation == .latest ? 1 : 120
        let samples = try await fetchQuantitySamples(
            type: quantityType,
            predicate: predicate,
            limit: sampleLimit
        )

        return samples.map { sample in
            let value = sample.quantity.doubleValue(for: descriptor.unit)
            return QueryResult.Entry(
                id: UUID(),
                source: .health,
                title: "\(descriptor.title): \(formattedValue(value, metric: metric))",
                body: nil,
                date: sample.startDate
            )
        }
    }

    func collectWorkoutEntries(
        interval: DateInterval?,
        aggregation: String,
        operation: BackendIntentOperation,
        filters: [String: AnyCodable]
    ) async throws -> [QueryResult.Entry] {
        let workoutType = workoutTypeFilter(from: filters)
        let workouts = try await fetchWorkouts(
            interval: interval,
            workoutType: workoutType,
            limit: operation == .latest ? 1 : 120
        )

        if aggregation == "count" || operation == .count || operation == .exists {
            return workouts.map { workout in
                QueryResult.Entry(
                    id: UUID(),
                    source: .health,
                    title: formattedWorkoutTitle(workout),
                    body: formattedWorkoutBody(workout),
                    date: workout.startDate
                )
            }
        }

        return workouts.map { workout in
            QueryResult.Entry(
                id: UUID(),
                source: .health,
                title: formattedWorkoutTitle(workout),
                body: formattedWorkoutBody(workout),
                date: workout.startDate
            )
        }
    }

    func collectSleepEntries(
        interval: DateInterval?,
        aggregation: String,
        operation: BackendIntentOperation
    ) async throws -> [QueryResult.Entry] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }

        let samples = try await fetchCategorySamples(
            type: sleepType,
            predicate: interval.map(samplePredicate(for:)),
            limit: operation == .latest ? 1 : 180
        )

        if aggregation == "duration" && operation != .latest {
            let totalSeconds = samples.reduce(0.0) { partial, sample in
                partial + sample.endDate.timeIntervalSince(sample.startDate)
            }
            guard totalSeconds > 0 else { return [] }
            let title = "Total sömn: \(formattedDuration(totalSeconds))"
            return [
                QueryResult.Entry(
                    id: UUID(),
                    source: .health,
                    title: title,
                    body: nil,
                    date: interval?.end ?? DateService.shared.now()
                )
            ]
        }

        return samples.map { sample in
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            return QueryResult.Entry(
                id: UUID(),
                source: .health,
                title: "Sömn: \(formattedDuration(duration))",
                body: nil,
                date: sample.startDate
            )
        }
    }

    func collectMindfulEntries(
        interval: DateInterval?,
        aggregation: String,
        operation: BackendIntentOperation
    ) async throws -> [QueryResult.Entry] {
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            return []
        }

        let samples = try await fetchCategorySamples(
            type: mindfulType,
            predicate: interval.map(samplePredicate(for:)),
            limit: operation == .latest ? 1 : 180
        )

        if aggregation == "duration" && operation != .latest {
            let totalSeconds = samples.reduce(0.0) { partial, sample in
                partial + sample.endDate.timeIntervalSince(sample.startDate)
            }
            guard totalSeconds > 0 else { return [] }
            return [
                QueryResult.Entry(
                    id: UUID(),
                    source: .health,
                    title: "Mindful tid: \(formattedDuration(totalSeconds))",
                    body: nil,
                    date: interval?.end ?? DateService.shared.now()
                )
            ]
        }

        return samples.map { sample in
            QueryResult.Entry(
                id: UUID(),
                source: .health,
                title: "Mindful-session",
                body: "Varaktighet: \(formattedDuration(sample.endDate.timeIntervalSince(sample.startDate)))",
                date: sample.startDate
            )
        }
    }

    func collectStateOfMindEntries(
        interval: DateInterval?,
        operation: BackendIntentOperation
    ) async throws -> [QueryResult.Entry] {
        if #available(iOS 17.0, *) {
            let type = HKObjectType.stateOfMindType()
            let samples = try await fetchSamples(
                type: type,
                predicate: interval.map(samplePredicate(for:)),
                limit: operation == .latest ? 1 : 120
            )
            return samples.map { sample in
                QueryResult.Entry(
                    id: UUID(),
                    source: .health,
                    title: "Sinnestillstånd registrerat",
                    body: nil,
                    date: sample.startDate
                )
            }
        } else {
            return []
        }
    }

    func samplePredicate(for interval: DateInterval) -> NSPredicate {
        HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: [.strictStartDate, .strictEndDate]
        )
    }

    func workoutTypeFilter(from filters: [String: AnyCodable]) -> HKWorkoutActivityType? {
        guard let raw = filters["workout_type"]?.value as? String else {
            return nil
        }
        switch raw.lowercased() {
        case "running":
            return .running
        case "cycling":
            return .cycling
        case "strength":
            return .traditionalStrengthTraining
        default:
            return nil
        }
    }

    func fetchStatisticsValue(
        for type: HKQuantityType,
        unit: HKUnit,
        options: HKStatisticsOptions,
        predicate: NSPredicate?
    ) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(returning: nil)
                    return
                }
                if options == .discreteAverage {
                    continuation.resume(returning: result.averageQuantity()?.doubleValue(for: unit))
                } else {
                    continuation.resume(returning: result.sumQuantity()?.doubleValue(for: unit))
                }
            }
            healthStore.execute(query)
        }
    }

    func fetchQuantitySamples(
        type: HKQuantityType,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let quantitySamples = (samples as? [HKQuantitySample]) ?? []
                continuation.resume(returning: quantitySamples)
            }
            healthStore.execute(query)
        }
    }

    func fetchCategorySamples(
        type: HKCategoryType,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let categorySamples = (samples as? [HKCategorySample]) ?? []
                continuation.resume(returning: categorySamples)
            }
            healthStore.execute(query)
        }
    }

    func fetchSamples(
        type: HKSampleType,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples ?? [])
            }
            healthStore.execute(query)
        }
    }

    func fetchWorkouts(
        interval: DateInterval?,
        workoutType: HKWorkoutActivityType?,
        limit: Int
    ) async throws -> [HKWorkout] {
        var predicates: [NSPredicate] = []
        if let interval {
            predicates.append(samplePredicate(for: interval))
        }
        if let workoutType {
            predicates.append(HKQuery.predicateForWorkouts(with: workoutType))
        }
        let predicate = predicates.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    func formattedAggregateTitle(
        metric: Metric,
        baseTitle: String,
        value: Double,
        aggregation: String
    ) -> String {
        let prefix: String
        switch aggregation {
        case "average":
            prefix = "Genomsnitt"
        default:
            prefix = "Totalt"
        }

        return "\(baseTitle) (\(prefix)): \(formattedValue(value, metric: metric))"
    }

    func formattedValue(_ value: Double, metric: Metric) -> String {
        switch metric {
        case .stepCount:
            return "\(formattedNumber(value, maxFractionDigits: 0)) steg"
        case .distance:
            return "\(formattedNumber(value, maxFractionDigits: 2)) km"
        case .activeEnergy:
            return "\(formattedNumber(value, maxFractionDigits: 0)) kcal"
        case .exerciseTime:
            return "\(formattedNumber(value, maxFractionDigits: 0)) min"
        case .heartRate, .restingHeartRate:
            return "\(formattedNumber(value, maxFractionDigits: 0)) slag/min"
        case .hrv:
            return "\(formattedNumber(value, maxFractionDigits: 0)) ms"
        case .respiratoryRate:
            return "\(formattedNumber(value, maxFractionDigits: 1)) andetag/min"
        case .bloodOxygen:
            return "\(formattedNumber(value * 100, maxFractionDigits: 1)) %"
        case .workout, .sleep, .mindfulSession, .stateOfMind:
            return formattedNumber(value, maxFractionDigits: 1)
        }
    }

    func formattedNumber(
        _ value: Double,
        maxFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxFractionDigits)f", value)
    }

    func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60.0).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours) h \(minutes) min"
        }
        return "\(minutes) min"
    }

    func formattedWorkoutTitle(_ workout: HKWorkout) -> String {
        let activity = localizedWorkoutType(workout.workoutActivityType)
        return "\(activity)"
    }

    func formattedWorkoutBody(_ workout: HKWorkout) -> String {
        let duration = formattedDuration(workout.duration)
        var parts: [String] = ["Varaktighet: \(duration)"]

        let distance = workout.totalDistance?.doubleValue(for: .meterUnit(with: .kilo))
        if let distance {
            parts.append("Distans: \(formattedNumber(distance, maxFractionDigits: 2)) km")
        }

        return parts.joined(separator: " · ")
    }

    func localizedWorkoutType(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:
            return "Löpning"
        case .cycling:
            return "Cykling"
        case .traditionalStrengthTraining:
            return "Styrketräning"
        case .walking:
            return "Promenad"
        default:
            return "Träningspass"
        }
    }
}
#endif
