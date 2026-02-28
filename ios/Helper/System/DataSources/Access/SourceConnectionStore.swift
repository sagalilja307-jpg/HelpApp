import Foundation

protocol SourceConnectionStoring: Sendable {
    func isEnabled(_ source: QuerySource) -> Bool
    func setEnabled(_ enabled: Bool, for source: QuerySource)
    func isOCREnabled(for source: QuerySource) -> Bool
    func setOCREnabled(_ enabled: Bool, for source: QuerySource)
    func hasImportedFiles() -> Bool
    func setHasImportedFiles(_ hasImportedFiles: Bool)
}

final class SourceConnectionStore: SourceConnectionStoring, @unchecked Sendable {
    static let shared = SourceConnectionStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isEnabled(_ source: QuerySource) -> Bool {
        if source == .photos {
            return true
        }

        if source == .health {
            let aggregateEnabled = defaults.bool(forKey: Self.healthEnabledKey)
            let anyHealthSourceEnabled = defaults.bool(forKey: Self.healthActivityEnabledKey)
                || defaults.bool(forKey: Self.healthSleepEnabledKey)
                || defaults.bool(forKey: Self.healthMentalEnabledKey)
                || defaults.bool(forKey: Self.healthVitalsEnabledKey)
            return aggregateEnabled || anyHealthSourceEnabled
        }

        guard let key = enabledKey(for: source) else { return false }
        return defaults.bool(forKey: key)
    }

    func setEnabled(_ enabled: Bool, for source: QuerySource) {
        if source == .photos {
            // Photos source is always on in current product rules.
            defaults.set(true, forKey: Self.photosEnabledKey)
            return
        }

        if source == .health {
            defaults.set(enabled, forKey: Self.healthEnabledKey)
            defaults.set(enabled, forKey: Self.healthActivityEnabledKey)
            defaults.set(enabled, forKey: Self.healthSleepEnabledKey)
            defaults.set(enabled, forKey: Self.healthMentalEnabledKey)
            defaults.set(enabled, forKey: Self.healthVitalsEnabledKey)
            return
        }

        guard let key = enabledKey(for: source) else { return }
        defaults.set(enabled, forKey: key)
    }

    func isOCREnabled(for source: QuerySource) -> Bool {
        guard let key = ocrKey(for: source) else { return false }
        return defaults.bool(forKey: key)
    }

    func setOCREnabled(_ enabled: Bool, for source: QuerySource) {
        guard let key = ocrKey(for: source) else { return }
        defaults.set(enabled, forKey: key)
    }

    func hasImportedFiles() -> Bool {
        defaults.bool(forKey: Self.filesImportedKey)
    }

    func setHasImportedFiles(_ hasImportedFiles: Bool) {
        defaults.set(hasImportedFiles, forKey: Self.filesImportedKey)
    }
}
