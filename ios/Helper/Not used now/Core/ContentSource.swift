// ContentSource.swift

import Foundation

/// Describes where the content came from.
/// Used for UX copy, filtering, and trust.
enum ContentSource: String, Codable {
    case sms
    case mail
    case screenshot
    case manual
    case siri
    case document
}
