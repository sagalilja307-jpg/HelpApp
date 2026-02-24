import Foundation

extension SourceConnectionStore {
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
