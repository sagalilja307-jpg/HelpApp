import Foundation
import Combine

enum MemorySourceID: String, CaseIterable, Identifiable {
    case calendar
    case reminders
    case mail
    case health

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar:
            return "Kalender"
        case .reminders:
            return "Påminnelser"
        case .mail:
            return "Mail"
        case .health:
            return "Hälsa"
        }
    }

    var subtitle: String {
        switch self {
        case .calendar:
            return "Händelser för överblick över dagen."
        case .reminders:
            return "Aktiva uppgifter och förfallotider."
        case .mail:
            return "Visar olästa mejl och senaste flöde."
        case .health:
            return "Använder hälsokällor du aktiverat i Datakällor."
        }
    }

    var iconName: String {
        switch self {
        case .calendar:
            return "calendar"
        case .reminders:
            return "checklist"
        case .mail:
            return "envelope"
        case .health:
            return "heart"
        }
    }
}

enum MemoryPermissionState: String {
    case unknown
    case granted
    case denied
    case unsupported

    var label: String {
        switch self {
        case .unknown:
            return "Ej frågad"
        case .granted:
            return "Tillåten"
        case .denied:
            return "Nekad"
        case .unsupported:
            return "Oaktiverad"
        }
    }
}

@MainActor
final class MemorySourceSettings: ObservableObject {
    private let dataSettingsStore: DataSettingsStore
    private let healthSources: [DataSourceID] = [
        .healthActivity,
        .sleep,
        .mentalHealth,
        .vitals
    ]

    @Published private(set) var calendarEnabled: Bool
    @Published private(set) var remindersEnabled: Bool
    @Published private(set) var mailEnabled: Bool
    @Published private(set) var healthEnabled: Bool

    @Published private(set) var permissionStates: [MemorySourceID: MemoryPermissionState]

    init(
        defaults: UserDefaults = .standard,
        sourceConnectionStore: SourceConnectionStore = .shared
    ) {
        self.dataSettingsStore = DataSettingsStore(
            sourceConnectionStore: sourceConnectionStore,
            defaults: defaults
        )
        self.calendarEnabled = false
        self.remindersEnabled = false
        self.mailEnabled = false
        self.healthEnabled = false
        self.permissionStates = Dictionary(
            uniqueKeysWithValues: MemorySourceID.allCases.map { ($0, .unknown) }
        )
        syncFromDataSettingsStore()
    }

    var anyEnabled: Bool {
        calendarEnabled || remindersEnabled || mailEnabled || healthEnabled
    }

    var hasDeniedEnabledSources: Bool {
        MemorySourceID.allCases.contains { source in
            isEnabled(source) && permissionState(for: source) == .denied
        }
    }

    func isSupported(_ source: MemorySourceID) -> Bool {
        switch source {
        case .calendar:
            return dataSettingsStore.isSourceSupported(.calendar)
        case .reminders:
            return dataSettingsStore.isSourceSupported(.reminders)
        case .mail:
            return dataSettingsStore.isSourceSupported(.mail)
        case .health:
            return healthSources.contains { dataSettingsStore.isSourceSupported($0) }
        }
    }

    func isEnabled(_ source: MemorySourceID) -> Bool {
        switch source {
        case .calendar:
            return calendarEnabled
        case .reminders:
            return remindersEnabled
        case .mail:
            return mailEnabled
        case .health:
            return healthEnabled
        }
    }

    func permissionState(for source: MemorySourceID) -> MemoryPermissionState {
        permissionStates[source] ?? .unknown
    }

    @discardableResult
    func setSource(_ source: MemorySourceID, enabled: Bool) async -> Bool {
        guard isSupported(source) else {
            permissionStates[source] = .unsupported
            syncFromDataSettingsStore()
            return false
        }

        switch source {
        case .calendar:
            let didEnable = await dataSettingsStore.setSource(.calendar, enabled: enabled)
            syncFromDataSettingsStore()
            return enabled ? didEnable : true
        case .reminders:
            let didEnable = await dataSettingsStore.setSource(.reminders, enabled: enabled)
            syncFromDataSettingsStore()
            return enabled ? didEnable : true
        case .mail:
            let didEnable = await dataSettingsStore.setSource(.mail, enabled: enabled)
            syncFromDataSettingsStore()
            return enabled ? didEnable : true
        case .health:
            if enabled {
                var enabledAny = false
                for healthSource in healthSources where dataSettingsStore.isSourceSupported(healthSource) {
                    let didEnable = await dataSettingsStore.setSource(healthSource, enabled: true)
                    enabledAny = enabledAny || didEnable
                }
                syncFromDataSettingsStore()
                return enabledAny
            } else {
                for healthSource in healthSources where dataSettingsStore.isSourceSupported(healthSource) {
                    _ = await dataSettingsStore.setSource(healthSource, enabled: false)
                }
                syncFromDataSettingsStore()
                return true
            }
        }
    }

    func refreshPermissionStatuses() async {
        await dataSettingsStore.refreshPermissionStatuses()
        syncFromDataSettingsStore()
    }

    private func syncFromDataSettingsStore() {
        calendarEnabled = dataSettingsStore.isSourceEnabled(.calendar)
        remindersEnabled = dataSettingsStore.isSourceEnabled(.reminders)
        mailEnabled = dataSettingsStore.isSourceEnabled(.mail)
        healthEnabled = healthSources.contains { dataSettingsStore.isSourceEnabled($0) }

        permissionStates[.calendar] = map(dataSettingsStore.permissionState(for: .calendar))
        permissionStates[.reminders] = map(dataSettingsStore.permissionState(for: .reminders))
        permissionStates[.mail] = map(dataSettingsStore.permissionState(for: .mail))
        permissionStates[.health] = aggregateHealthPermissionState()
    }

    private func aggregateHealthPermissionState() -> MemoryPermissionState {
        let supportedHealthSources = healthSources.filter { dataSettingsStore.isSourceSupported($0) }
        guard !supportedHealthSources.isEmpty else { return .unsupported }

        let enabledHealthSources = supportedHealthSources.filter { dataSettingsStore.isSourceEnabled($0) }
        guard !enabledHealthSources.isEmpty else { return .unknown }

        let states = enabledHealthSources.map { dataSettingsStore.permissionState(for: $0) }

        if states.contains(.denied) {
            return .denied
        }
        if states.contains(.granted) {
            return .granted
        }
        return .unknown
    }

    private func map(_ status: DataPermissionState) -> MemoryPermissionState {
        switch status {
        case .unknown:
            return .unknown
        case .granted:
            return .granted
        case .denied:
            return .denied
        }
    }
}
