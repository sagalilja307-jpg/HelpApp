import Foundation
import SwiftUI
import Combine

@MainActor
final class DataSettingsStore: ObservableObject {
    private static let cameraEnabledKey = "helper.stage3.camera.enabled"
    private static let healthActivityEnabledKey = "helper.stage4.health.activity.enabled"
    private static let sleepEnabledKey = "helper.stage4.health.sleep.enabled"
    private static let mentalHealthEnabledKey = "helper.stage4.health.mental.enabled"
    private static let vitalsEnabledKey = "helper.stage4.health.vitals.enabled"

    private let sourceConnectionStore: SourceConnectionStore
    private let defaults: UserDefaults

    @Published private(set) var domainEnabled: [DataDomainID: Bool] = [:]
    @Published private(set) var sourceEnabled: [DataSourceID: Bool] = [:]
    @Published private(set) var permissionStates: [DataSourceID: DataPermissionState] = [:]

    init(
        sourceConnectionStore: SourceConnectionStore,
        defaults: UserDefaults = .standard
    ) {
        self.sourceConnectionStore = sourceConnectionStore
        self.defaults = defaults
        hydrateFromStorage()
    }

    func isDomainEnabled(_ id: DataDomainID) -> Bool {
        domainEnabled[id] ?? false
    }

    func isSourceEnabled(_ id: DataSourceID) -> Bool {
        sourceEnabled[id] ?? false
    }

    func permissionState(for source: DataSourceID) -> DataPermissionState {
        permissionStates[source] ?? .unknown
    }

    func isSourceSupported(_ source: DataSourceID) -> Bool {
        switch source {
        case .calendar, .reminders, .contacts, .mail, .files, .photos, .camera, .location:
            return true
        case .healthActivity, .sleep, .mentalHealth, .vitals:
            return PermissionManager.shared.isHealthDataAvailable
        case .notifications:
            return false
        }
    }

    func setDomain(_ domain: DataDomain, enabled: Bool) {
        setDomainEnabled(domain.id, enabled: enabled)

        if !enabled {
            for source in domain.sources where isSourceSupported(source.id) {
                setSourceEnabledLocally(source.id, enabled: false)
            }
        }
    }

    @discardableResult
    func setSource(_ source: DataSourceID, enabled: Bool) async -> Bool {
        guard isSourceSupported(source) else {
            sourceEnabled[source] = false
            return false
        }

        // Optimistic UI update; roll back if permission fails.
        sourceEnabled[source] = enabled

        guard enabled else {
            setSourceEnabledLocally(source, enabled: false)
            return true
        }

        if source == .mail, OAuthTokenManager.shared.hasStoredToken() == false {
            permissionStates[source] = .unknown
            setSourceEnabledLocally(source, enabled: false)
            return false
        }

        if let permissionType = permissionType(for: source) {
            var status = await PermissionManager.shared.status(for: permissionType)
            if status == .notDetermined {
                do {
                    status = try await PermissionManager.shared.requestAccess(for: permissionType)
                } catch {
                    status = .denied
                }
            }

            let mapped = mapPermissionStatus(status)
            permissionStates[source] = mapped

            guard mapped == .granted else {
                setSourceEnabledLocally(source, enabled: false)
                return false
            }
        } else {
            permissionStates[source] = syntheticPermissionState(for: source)
        }

        setSourceEnabledLocally(source, enabled: true)
        if let domain = domainForSource(source), isDomainEnabled(domain.id) == false {
            setDomainEnabled(domain.id, enabled: true)
        }
        return true
    }

    func refreshPermissionStatuses() async {
        var nextStates: [DataSourceID: DataPermissionState] = permissionStates

        for source in DataSourceID.allCases {
            guard isSourceSupported(source) else {
                nextStates[source] = .unknown
                continue
            }

            if let permissionType = permissionType(for: source) {
                let status = await PermissionManager.shared.status(for: permissionType)
                nextStates[source] = mapPermissionStatus(status)
            } else {
                nextStates[source] = syntheticPermissionState(for: source)
            }
        }

        permissionStates = nextStates
    }

    func hasDeniedEnabledSources(in domain: DataDomain) -> Bool {
        domain.sources.contains { source in
            isSourceSupported(source.id)
                && permissionState(for: source.id) == .denied
        }
    }

    private func hydrateFromStorage() {
        var nextSourceEnabled: [DataSourceID: Bool] = [:]

        for source in DataSourceID.allCases {
            guard isSourceSupported(source) else {
                nextSourceEnabled[source] = false
                continue
            }

            if let querySource = querySource(for: source) {
                nextSourceEnabled[source] = sourceConnectionStore.isEnabled(querySource)
            } else if source == .camera {
                nextSourceEnabled[source] = defaults.bool(forKey: Self.cameraEnabledKey)
            } else if source == .healthActivity {
                nextSourceEnabled[source] = defaults.bool(forKey: Self.healthActivityEnabledKey)
            } else if source == .sleep {
                nextSourceEnabled[source] = defaults.bool(forKey: Self.sleepEnabledKey)
            } else if source == .mentalHealth {
                nextSourceEnabled[source] = defaults.bool(forKey: Self.mentalHealthEnabledKey)
            } else if source == .vitals {
                nextSourceEnabled[source] = defaults.bool(forKey: Self.vitalsEnabledKey)
            } else {
                nextSourceEnabled[source] = false
            }
        }

        sourceEnabled = nextSourceEnabled

        var nextDomainEnabled: [DataDomainID: Bool] = [:]
        for domain in DomainCatalog.all {
            let key = domainKey(domain.id)
            if let storedValue = defaults.object(forKey: key) as? Bool {
                nextDomainEnabled[domain.id] = storedValue
            } else {
                nextDomainEnabled[domain.id] = domain.sources.contains { nextSourceEnabled[$0.id] == true }
            }
        }

        domainEnabled = nextDomainEnabled

        var nextPermissionStates: [DataSourceID: DataPermissionState] = [:]
        for source in DataSourceID.allCases {
            nextPermissionStates[source] = isSourceSupported(source) ? syntheticPermissionState(for: source) : .unknown
        }
        permissionStates = nextPermissionStates
    }

    private func setDomainEnabled(_ id: DataDomainID, enabled: Bool) {
        domainEnabled[id] = enabled
        defaults.set(enabled, forKey: domainKey(id))
    }

    private func setSourceEnabledLocally(_ source: DataSourceID, enabled: Bool) {
        sourceEnabled[source] = enabled
        if let querySource = querySource(for: source) {
            sourceConnectionStore.setEnabled(enabled, for: querySource)
            return
        }

        if source == .camera {
            defaults.set(enabled, forKey: Self.cameraEnabledKey)
            return
        }

        switch source {
        case .healthActivity:
            defaults.set(enabled, forKey: Self.healthActivityEnabledKey)
        case .sleep:
            defaults.set(enabled, forKey: Self.sleepEnabledKey)
        case .mentalHealth:
            defaults.set(enabled, forKey: Self.mentalHealthEnabledKey)
        case .vitals:
            defaults.set(enabled, forKey: Self.vitalsEnabledKey)
        default:
            break
        }
    }

    private func mapPermissionStatus(_ status: AppPermissionStatus) -> DataPermissionState {
        switch status {
        case .notDetermined:
            return .unknown
        case .granted:
            return .granted
        case .denied:
            return .denied
        }
    }

    private func syntheticPermissionState(for source: DataSourceID) -> DataPermissionState {
        switch source {
        case .mail:
            return OAuthTokenManager.shared.hasStoredToken() ? .granted : .unknown
        case .files:
            return .granted
        default:
            return .unknown
        }
    }

    private func querySource(for source: DataSourceID) -> QuerySource? {
        switch source {
        case .calendar:
            return .calendar
        case .reminders:
            return .reminders
        case .contacts:
            return .contacts
        case .mail:
            return .mail
        case .files:
            return .files
        case .photos:
            return .photos
        case .location:
            return .location
        case .notifications, .healthActivity, .sleep, .mentalHealth, .vitals:
            return nil
        case .camera:
            return nil
        }
    }

    private func permissionType(for source: DataSourceID) -> AppPermissionType? {
        switch source {
        case .calendar:
            return .calendar
        case .reminders:
            return .reminder
        case .contacts:
            return .contacts
        case .photos:
            return .photos
        case .camera:
            return .camera
        case .location:
            return .location
        case .healthActivity:
            return .healthActivity
        case .sleep:
            return .healthSleep
        case .mentalHealth:
            return .healthMental
        case .vitals:
            return .healthVitals
        case .mail, .files, .notifications:
            return nil
        }
    }

    private func domainForSource(_ source: DataSourceID) -> DataDomain? {
        DomainCatalog.all.first(where: { domain in
            domain.sources.contains(where: { $0.id == source })
        })
    }

    private func domainKey(_ domainID: DataDomainID) -> String {
        "helper.domain.\(domainID.rawValue).enabled"
    }
}
