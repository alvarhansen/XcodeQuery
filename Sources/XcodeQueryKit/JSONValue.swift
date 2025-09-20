import Foundation

// A minimal JSON value to encode dynamic GraphQL results
public enum JSONValue: Encodable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case bool(Bool)
    case number(Double)
    case null

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let dict):
            try container.encode(JSONObject(dict))
        case .array(let arr):
            try container.encode(arr)
        case .string(let s):
            try container.encode(s)
        case .bool(let b):
            try container.encode(b)
        case .number(let n):
            try container.encode(n)
        case .null:
            try container.encodeNil()
        }
    }

    // Helper for building easily
    static func from(_ s: String) -> JSONValue { .string(s) }
    static func from(_ b: Bool) -> JSONValue { .bool(b) }
    static func from<T: BinaryInteger>(_ n: T) -> JSONValue { .number(Double(n)) }
    static func from<T: BinaryFloatingPoint>(_ n: T) -> JSONValue { .number(Double(n)) }

    private struct JSONObject: Encodable {
        let dict: [String: JSONValue]
        init(_ d: [String: JSONValue]) { self.dict = d }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (k, v) in dict { try container.encode(v, forKey: DynamicCodingKey(stringValue: k)!) }
        }
        struct DynamicCodingKey: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { return nil }
        }
    }
}

