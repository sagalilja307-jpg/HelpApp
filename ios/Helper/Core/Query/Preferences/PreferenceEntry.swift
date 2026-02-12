import Foundation

public struct PreferenceEntry: Codable {
    public var key: PreferenceKey
    public var value: PreferenceValue
    public var scope: PreferenceScope
    public var source: PreferenceSource
    public var updatedAt: Date

    public init(
        key: PreferenceKey,
        value: PreferenceValue,
        scope: PreferenceScope,
        source: PreferenceSource,
        updatedAt: Date = Date()
    ) {
        self.key = key
        self.value = value
        self.scope = scope
        self.source = source
        self.updatedAt = updatedAt
    }
}
