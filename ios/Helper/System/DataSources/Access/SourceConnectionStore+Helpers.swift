import Foundation

extension SourceConnectionStore {
    static let calendarEnabledKey = "helper.stage1.calendar.enabled"
    static let remindersEnabledKey = "helper.stage1.reminders.enabled"
    static let contactsEnabledKey = "helper.stage2.contacts.enabled"
    static let photosEnabledKey = "helper.stage2.photos.enabled"
    static let filesEnabledKey = "helper.stage2.files.enabled"
    static let locationEnabledKey = "helper.stage3.location.enabled"
    static let mailEnabledKey = "helper.stage3.mail.enabled"
    static let healthEnabledKey = "helper.stage4.health.enabled"
    static let healthActivityEnabledKey = "helper.stage4.health.activity.enabled"
    static let healthSleepEnabledKey = "helper.stage4.health.sleep.enabled"
    static let healthMentalEnabledKey = "helper.stage4.health.mental.enabled"
    static let healthVitalsEnabledKey = "helper.stage4.health.vitals.enabled"
    static let photosOCREnabledKey = "helper.stage2.photos.ocr.enabled"
    static let filesOCREnabledKey = "helper.stage2.files.ocr.enabled"
    static let filesImportedKey = "helper.stage2.files.has_imported"

    func enabledKey(for source: QuerySource) -> String? {
        switch source {
        case .calendar:
            return Self.calendarEnabledKey
        case .reminders:
            return Self.remindersEnabledKey
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
        case .health:
            return Self.healthEnabledKey
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
