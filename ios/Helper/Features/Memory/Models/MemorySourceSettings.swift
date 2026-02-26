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
            return "Kommer i en senare version."
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
    private enum Keys {
        static let calendarEnabled = "helper.memory.calendar.enabled"
        static let remindersEnabled = "helper.memory.reminders.enabled"
        static let mailEnabled = "helper.memory.mail.enabled"
        static let healthEnabled = "helper.memory.health.enabled"
    }

    private let defaults: UserDefaults

    @Published private(set) var calendarEnabled: Bool
    @Published private(set) var remindersEnabled: Bool
    @Published private(set) var mailEnabled: Bool
    @Published private(set) var healthEnabled: Bool

    @Published private(set) var permissionStates: [MemorySourceID: MemoryPermissionState]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.calendarEnabled = defaults.bool(forKey: Keys.calendarEnabled)
        self.remindersEnabled = defaults.bool(forKey: Keys.remindersEnabled)
        self.mailEnabled = defaults.bool(forKey: Keys.mailEnabled)
        self.healthEnabled = false

        self.permissionStates = [.health: .unsupported]
        for source in MemorySourceID.allCases where source != .health {
            self.permissionStates[source] = .unknown
        }
    }

    var anyEnabled: Bool {
        calendarEnabled || remindersEnabled || mailEnabled
    }

    var hasDeniedEnabledSources: Bool {
        MemorySourceID.allCases.contains { source in
            isEnabled(source) && permissionState(for: source) == .denied
        }
    }

    func isSupported(_ source: MemorySourceID) -> Bool {
        source != .health
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
            setEnabled(source, enabled: false)
            permissionStates[source] = .unsupported
            return false
        }

        guard enabled else {
            setEnabled(source, enabled: false)
            await refreshPermissionStatus(for: source)
            return true
        }

        switch source {
        case .mail:
            let isGranted = OAuthTokenManager.shared.hasValidToken()
            permissionStates[source] = isGranted ? .granted : .unknown
            setEnabled(source, enabled: isGranted)
            return isGranted
        case .calendar, .reminders:
            let permissionType: AppPermissionType = source == .calendar ? .calendar : .reminder
            var status = await PermissionManager.shared.status(for: permissionType)
            if status == .notDetermined {
                do {
                    status = try await PermissionManager.shared.requestAccess(for: permissionType)
                } catch {
                    status = .denied
                }
            }

            let mapped = map(status)
            permissionStates[source] = mapped
            let granted = mapped == .granted
            setEnabled(source, enabled: granted)
            return granted
        case .health:
            return false
        }
    }

    func refreshPermissionStatuses() async {
        for source in MemorySourceID.allCases {
            await refreshPermissionStatus(for: source)
            if !isSupported(source) {
                setEnabled(source, enabled: false)
                continue
            }
            if permissionState(for: source) != .granted {
                setEnabled(source, enabled: false)
            }
        }
    }

    private func refreshPermissionStatus(for source: MemorySourceID) async {
        guard isSupported(source) else {
            permissionStates[source] = .unsupported
            return
        }

        switch source {
        case .calendar:
            permissionStates[source] = map(await PermissionManager.shared.status(for: .calendar))
        case .reminders:
            permissionStates[source] = map(await PermissionManager.shared.status(for: .reminder))
        case .mail:
            permissionStates[source] = OAuthTokenManager.shared.hasValidToken() ? .granted : .unknown
        case .health:
            permissionStates[source] = .unsupported
        }
    }

    private func setEnabled(_ source: MemorySourceID, enabled: Bool) {
        switch source {
        case .calendar:
            calendarEnabled = enabled
            defaults.set(enabled, forKey: Keys.calendarEnabled)
        case .reminders:
            remindersEnabled = enabled
            defaults.set(enabled, forKey: Keys.remindersEnabled)
        case .mail:
            mailEnabled = enabled
            defaults.set(enabled, forKey: Keys.mailEnabled)
        case .health:
            healthEnabled = false
            defaults.set(false, forKey: Keys.healthEnabled)
        }
    }

    private func map(_ status: AppPermissionStatus) -> MemoryPermissionState {
        switch status {
        case .notDetermined:
            return .unknown
        case .granted:
            return .granted
        case .denied:
            return .denied
        }
    }
}
