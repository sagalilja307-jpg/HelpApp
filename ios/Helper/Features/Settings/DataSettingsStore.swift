import Foundation
import SwiftUI
import Combine

@MainActor
final class DataSettingsStore: ObservableObject {
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
        case .calendar, .reminders, .contacts, .mail, .files, .photos, .location:
            return true
        case .notifications, .camera, .healthActivity, .sleep, .mentalHealth, .vitals:
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
            guard isSourceSupported(source), let querySource = querySource(for: source) else {
                nextSourceEnabled[source] = false
                continue
            }
            nextSourceEnabled[source] = sourceConnectionStore.isEnabled(querySource)
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
        case .notifications, .camera, .healthActivity, .sleep, .mentalHealth, .vitals:
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
        case .location:
            return .location
        case .mail, .files, .notifications, .camera, .healthActivity, .sleep, .mentalHealth, .vitals:
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
