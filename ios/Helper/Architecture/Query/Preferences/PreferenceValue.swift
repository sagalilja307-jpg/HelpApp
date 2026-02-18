import Foundation

public struct PreferenceValue: Codable, Sendable {

    public enum Kind: String, Codable {
        case bool
        case string
        case stringList
    }

    public let kind: Kind
    public let boolValue: Bool?
    public let stringValue: String?
    public let stringListValue: [String]?

    private init(
        kind: Kind,
        boolValue: Bool? = nil,
        stringValue: String? = nil,
        stringListValue: [String]? = nil
    ) {
        self.kind = kind
        self.boolValue = boolValue
        self.stringValue = stringValue
        self.stringListValue = stringListValue
    }

    public static func bool(_ value: Bool) -> PreferenceValue {
        .init(kind: .bool, boolValue: value)
    }

    public static func string(_ value: String) -> PreferenceValue {
        .init(kind: .string, stringValue: value)
    }

    public static func stringList(_ value: [String]) -> PreferenceValue {
        .init(kind: .stringList, stringListValue: value)
    }
}
