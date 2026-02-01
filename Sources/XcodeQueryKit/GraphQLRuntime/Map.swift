import Foundation

public enum Map: Equatable {
    case undefined
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([Map])
    case dictionary([String: Map])

    public init(_ value: Bool) {
        self = .bool(value)
    }

    public init(_ value: String) {
        self = .string(value)
    }

    public init<T: BinaryInteger>(_ value: T) {
        self = .number(Double(value))
    }

    public init<T: BinaryFloatingPoint>(_ value: T) {
        self = .number(Double(value))
    }

    public var isUndefined: Bool {
        if case .undefined = self { return true }
        return false
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var int: Int? {
        if case .number(let n) = self { return Int(n) }
        return nil
    }

    public var double: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    public var doubleValue: Double {
        if case .number(let n) = self { return n }
        return 0
    }

    public var array: [Map]? {
        if case .array(let arr) = self { return arr }
        return nil
    }

    public var dictionary: [String: Map]? {
        if case .dictionary(let dict) = self { return dict }
        return nil
    }

    public subscript(key: String) -> Map {
        guard case .dictionary(let dict) = self else { return .undefined }
        return dict[key] ?? .undefined
    }
}
