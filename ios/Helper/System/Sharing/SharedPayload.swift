import Foundation

enum SharedPayloadVersion: String, Codable, Sendable {
    case v1
}

enum SharedItemKind: String, Codable, Sendable {
    case text
    case url
    case imageFile
    case pdfFile
}

struct SharedItemPayload: Codable, Sendable {
    let id: String
    let kind: SharedItemKind
    let value: String
    let source: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case value
        case source
        case createdAt = "created_at"
    }
}

struct SharedItemsEnvelope: Codable, Sendable {
    let version: SharedPayloadVersion
    let items: [SharedItemPayload]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case version
        case items
        case createdAt = "created_at"
    }
}
