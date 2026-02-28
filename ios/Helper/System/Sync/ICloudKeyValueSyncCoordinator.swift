import Foundation

@MainActor
final class ICloudKeyValueSyncCoordinator {
    private enum Keys {
        static let syncEnabled = "helper.icloud.sync.enabled"
    }

    private let defaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore

    private var hasStarted = false
    private var isApplyingRemoteChanges = false
    private var cloudObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        cloudStore: NSUbiquitousKeyValueStore = .default
    ) {
        self.defaults = defaults
        self.cloudStore = cloudStore

        if defaults.object(forKey: Keys.syncEnabled) == nil {
            defaults.set(true, forKey: Keys.syncEnabled)
        }
    }

    deinit {
        if let cloudObserver {
            NotificationCenter.default.removeObserver(cloudObserver)
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    var isSyncEnabled: Bool {
        defaults.object(forKey: Keys.syncEnabled) as? Bool ?? true
    }

    var hasICloudAccount: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] notification in
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            Task { @MainActor [weak self] in
                self?.handleCloudStoreChange(changedKeys: changedKeys)
            }
        }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleLocalDefaultsChange()
            }
        }

        guard isSyncEnabled else { return }
        syncNow()
    }

    func setSyncEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.syncEnabled)
        guard enabled else { return }
        syncNow()
    }

    func syncNow() {
        guard isSyncEnabled else { return }

        cloudStore.synchronize()
        pullFromCloud(keys: nil)
        pushToCloud()
        cloudStore.synchronize()
    }

    private func handleCloudStoreChange(changedKeys: [String]?) {
        guard isSyncEnabled else { return }
        pullFromCloud(keys: changedKeys)
    }

    private func handleLocalDefaultsChange() {
        guard isSyncEnabled else { return }
        guard !isApplyingRemoteChanges else { return }
        pushToCloud()
    }

    private func pullFromCloud(keys: [String]?) {
        let incomingKeys: [String]
        if let keys {
            incomingKeys = keys.filter(shouldSync)
        } else {
            incomingKeys = cloudStore.dictionaryRepresentation.keys.filter(shouldSync)
        }

        guard !incomingKeys.isEmpty else { return }

        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        for key in incomingKeys {
            if let value = cloudStore.object(forKey: key) {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private func pushToCloud() {
        let values = defaults.dictionaryRepresentation()

        for (key, rawValue) in values where shouldSync(key) {
            guard let cloudValue = cloudSupportedValue(from: rawValue) else { continue }
            cloudStore.set(cloudValue, forKey: key)
        }
    }

    private func shouldSync(_ key: String) -> Bool {
        key.hasPrefix("helper.") && key != Keys.syncEnabled
    }

    private func cloudSupportedValue(from value: Any) -> Any? {
        switch value {
        case let value as NSString:
            return value
        case let value as NSNumber:
            return value
        case let value as NSData:
            return value
        case let value as NSDate:
            return value
        case let value as [Any]:
            let normalized = value.compactMap(cloudSupportedValue(from:))
            return normalized.count == value.count ? normalized : nil
        case let value as [String: Any]:
            var normalized: [String: Any] = [:]
            for (key, nestedValue) in value {
                guard let supported = cloudSupportedValue(from: nestedValue) else {
                    return nil
                }
                normalized[key] = supported
            }
            return normalized
        default:
            return nil
        }
    }
}
