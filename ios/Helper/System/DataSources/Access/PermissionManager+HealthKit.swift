import Foundation

#if canImport(HealthKit)
@preconcurrency import HealthKit
#endif

extension PermissionManager {

    var isHealthDataAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    func healthPermissionStatus(for type: AppPermissionType) async -> AppPermissionStatus {
        #if canImport(HealthKit)
        guard isHealthDataAvailable else { return .denied }
        let readTypes = healthReadObjectTypes(for: type)
        guard !readTypes.isEmpty else { return .denied }

        do {
            let requestStatus = try await healthAuthorizationRequestStatus(readTypes: readTypes)
            switch requestStatus {
            case .shouldRequest, .unknown:
                return .notDetermined
            case .unnecessary:
                // For read permissions, HealthKit does not expose per-type granted/denied.
                // "unnecessary" means authorization has already been resolved for this set.
                return .granted
            @unknown default:
                return .notDetermined
            }
        } catch {
            return .notDetermined
        }
        #else
        return .denied
        #endif
    }

    func requestHealthAccess(for type: AppPermissionType) async throws -> AppPermissionStatus {
        #if canImport(HealthKit)
        guard isHealthDataAvailable else { return .denied }

        let readTypes = healthReadObjectTypes(for: type)
        guard !readTypes.isEmpty else { return .denied }

        let requestStatus = try await healthAuthorizationRequestStatus(readTypes: readTypes)
        guard requestStatus == .shouldRequest else {
            return .granted
        }

        let success: Bool = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: success)
            }
        }

        guard success else { return .notDetermined }
        return await healthPermissionStatus(for: type)
        #else
        return .denied
        #endif
    }

    #if canImport(HealthKit)
    private func healthAuthorizationRequestStatus(readTypes: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKAuthorizationRequestStatus, Error>) in
            healthStore.getRequestStatusForAuthorization(toShare: Set<HKSampleType>(), read: readTypes) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: status)
            }
        }
    }

    private func healthReadObjectTypes(for type: AppPermissionType) -> Set<HKObjectType> {
        switch type {
        case .healthActivity:
            return activityHealthTypes()
        case .healthSleep:
            return sleepHealthTypes()
        case .healthMental:
            return mentalHealthTypes()
        case .healthVitals:
            return vitalsHealthTypes()
        default:
            return []
        }
    }

    private func activityHealthTypes() -> Set<HKObjectType> {
        var result: Set<HKObjectType> = []

        let quantities: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .distanceWalkingRunning,
            .activeEnergyBurned,
            .appleExerciseTime,
        ]

        for identifier in quantities {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                result.insert(type)
            }
        }

        result.insert(HKWorkoutType.workoutType())
        return result
    }

    private func sleepHealthTypes() -> Set<HKObjectType> {
        guard let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }
        return [sleep]
    }

    private func mentalHealthTypes() -> Set<HKObjectType> {
        var result: Set<HKObjectType> = []

        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            result.insert(mindful)
        }

        result.insert(HKObjectType.stateOfMindType())

        return result
    }

    private func vitalsHealthTypes() -> Set<HKObjectType> {
        var result: Set<HKObjectType> = []
        let identifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .respiratoryRate,
            .oxygenSaturation,
        ]

        for identifier in identifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                result.insert(type)
            }
        }

        return result
    }
    #endif
}
