import Foundation

/// A flexible CodingKey that accepts any string, used for backward-compatible decoding.
struct FlexKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { self.stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Decoder {
    func flexContainer() throws -> KeyedDecodingContainer<FlexKey> {
        try container(keyedBy: FlexKey.self)
    }
}

extension KeyedDecodingContainer where K == FlexKey {
    /// Decode a required value, trying keys in order (short key first, then legacy).
    func decode<T: Decodable>(_ type: T.Type, _ keys: String...) throws -> T {
        for key in keys {
            let k = FlexKey(key)
            if contains(k) {
                return try decode(type, forKey: k)
            }
        }
        throw DecodingError.keyNotFound(
            FlexKey(keys[0]),
            .init(codingPath: codingPath, debugDescription: "None of keys \(keys) found")
        )
    }

    /// Decode an optional value, trying keys in order.
    func opt<T: Decodable>(_ type: T.Type, _ keys: String...) throws -> T? {
        for key in keys {
            let k = FlexKey(key)
            if contains(k) {
                return try decodeIfPresent(type, forKey: k)
            }
        }
        return nil
    }

    /// Check if any of the given keys exist.
    func has(_ keys: String...) -> Bool {
        keys.contains { contains(FlexKey($0)) }
    }
}
