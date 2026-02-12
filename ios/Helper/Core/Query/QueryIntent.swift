import Foundation

/// The system's meaning-language for what the user asks.
enum QueryIntent: String, Codable, CaseIterable, Sendable {
    case summary
    case recall
    case overview
    case memoryLookup
    case unknown
}
