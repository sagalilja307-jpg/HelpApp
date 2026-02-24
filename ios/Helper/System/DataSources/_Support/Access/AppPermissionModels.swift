import Foundation

enum AppPermissionType {
    case calendar
    case reminder
    case notification
    case camera
    case contacts
    case photos
    case location
}

enum AppPermissionStatus {
    case notDetermined
    case granted
    case denied
}
