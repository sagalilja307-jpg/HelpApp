import Foundation

public struct AnyCodable: Codable, Sendable, Equatable {
    public nonisolated(unsafe) let value: Any

    public nonisolated init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { value = v; return }
        if let v = try? container.decode(Int.self) { value = v; return }
        if let v = try? container.decode(Double.self) { value = v; return }
        if let v = try? container.decode(String.self) { value = v; return }
        if let v = try? container.decode([AnyCodable].self) {
            value = v.map(\.value)
            return
        }
        if let v = try? container.decode([String: AnyCodable].self) {
            value = v.mapValues(\.value)
            return
        }

        value = NSNull()
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:
            try container.encode(v)
        case let v as Int:
            try container.encode(v)
        case let v as Double:
            try container.encode(v)
        case let v as String:
            try container.encode(v)
        case let v as [Any]:
            try container.encode(v.map(AnyCodable.init))
        case let v as [String: Any]:
            try container.encode(v.mapValues(AnyCodable.init))
        case is NSNull:
            try container.encodeNil()
        default:
            // Fallback for unknown types
            try container.encode(String(describing: value))
        }
    }

    private var unwrappedValue: Any { value }
}

extension AnyCodable {
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull):
            return true
        case let (l as Bool, r as Bool):
            return l == r
        case let (l as Int, r as Int):
            return l == r
        case let (l as Double, r as Double):
            return l == r
        case let (l as String, r as String):
            return l == r
        case let (l as [Any], r as [Any]):
            guard l.count == r.count else { return false }
            return zip(l, r).allSatisfy { AnyCodable($0) == AnyCodable($1) }
        case let (l as [String: Any], r as [String: Any]):
            guard l.count == r.count, Set(l.keys) == Set(r.keys) else { return false }
            return l.allSatisfy { key, lv in
                guard let rv = r[key] else { return false }
                return AnyCodable(lv) == AnyCodable(rv)
            }
        default:
            return false
        }
    }
}
