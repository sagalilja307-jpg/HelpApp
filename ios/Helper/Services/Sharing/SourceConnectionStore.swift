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
        // On first run, ensure the source-enabled keys exist and default to true
        // so sources are opt-in enabled in app settings (OS permissions still required).
        let enabledKeys = [
            Self.contactsEnabledKey,
            Self.photosEnabledKey,
            Self.filesEnabledKey,
            Self.locationEnabledKey,
            Self.mailEnabledKey
        ]
        for key in enabledKeys {
            if defaults.object(forKey: key) == nil {
                defaults.set(true, forKey: key)
            }
        }
    }

    func isEnabled(_ source: QuerySource) -> Bool {
        if source == .photos {
            return true
        }
        guard let key = enabledKey(for: source) else { return false }
        return defaults.bool(forKey: key)
    }

    func setEnabled(_ enabled: Bool, for source: QuerySource) {
        if source == .photos {
            defaults.set(true, forKey: Self.photosEnabledKey)
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

private extension SourceConnectionStore {
    static let contactsEnabledKey = "helper.stage2.contacts.enabled"
    static let photosEnabledKey = "helper.stage2.photos.enabled"
    static let filesEnabledKey = "helper.stage2.files.enabled"
    static let locationEnabledKey = "helper.stage3.location.enabled"
    static let mailEnabledKey = "helper.stage3.mail.enabled"
    static let photosOCREnabledKey = "helper.stage2.photos.ocr.enabled"
    static let filesOCREnabledKey = "helper.stage2.files.ocr.enabled"
    static let filesImportedKey = "helper.stage2.files.has_imported"

    func enabledKey(for source: QuerySource) -> String? {
        switch source {
        case .contacts:
            return Self.contactsEnabledKey
        case .photos:
            return Self.photosEnabledKey
        case .files:
            return Self.filesEnabledKey
        case .location:
            return Self.locationEnabledKey
        case .mail:
            return Self.mailEnabledKey
        default:
            return nil
        }
    }

    func ocrKey(for source: QuerySource) -> String? {
        switch source {
        case .photos:
            return Self.photosOCREnabledKey
        case .files:
            return Self.filesOCREnabledKey
        default:
            return nil
        }
    }
}
// MOVE FILE TO: /Users/sagalilja/Library/Mobile Documents/com~apple~CloudDocs/Helper/ios/Helper/Data/Services/Sharing/SourceConnectionStore.swift
