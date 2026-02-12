import Foundation

public enum JSONCodec {

    public enum JSONCodecError: LocalizedError {
        case stringEncodingFailed
        case invalidUTF8String

        public var errorDescription: String? {
            switch self {
            case .stringEncodingFailed:
                return "Failed to encode data to UTF-8 string."
            case .invalidUTF8String:
                return "Provided string is not valid UTF-8."
            }
        }
    }

    /// Encodes any Encodable value to a JSON string.
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw JSONCodecError.stringEncodingFailed
        }
        return jsonString
    }

    /// Decodes a JSON string into a Decodable type.
    public static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw JSONCodecError.invalidUTF8String
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
