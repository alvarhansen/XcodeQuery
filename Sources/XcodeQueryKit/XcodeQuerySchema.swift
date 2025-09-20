import Foundation

public indirect enum XQSTypeRef: Equatable, Sendable {
    case named(String, nonNull: Bool = false)
    case list(of: XQSTypeRef, nonNull: Bool = false, elementNonNull: Bool = false)

    public static func nn(_ name: String) -> XQSTypeRef { .named(name, nonNull: true) }
    public static func listNN(_ name: String) -> XQSTypeRef { .list(of: .named(name), nonNull: true, elementNonNull: true) }
}

public struct XQArgument: Equatable, Sendable {
    public var name: String
    public var type: XQSTypeRef
    public var defaultValue: String?
    public init(_ name: String, _ type: XQSTypeRef, defaultValue: String? = nil) { self.name = name; self.type = type; self.defaultValue = defaultValue }
}

public struct XQField: Equatable, Sendable {
    public var name: String
    public var args: [XQArgument]
    public var type: XQSTypeRef
    public init(_ name: String, args: [XQArgument] = [], type: XQSTypeRef) { self.name = name; self.args = args; self.type = type }
}

public struct XQObjectType: Equatable, Sendable {
    public var name: String
    public var fields: [XQField]
    public init(_ name: String, fields: [XQField]) { self.name = name; self.fields = fields }
}

public struct XQEnumType: Equatable, Sendable {
    public var name: String
    public var cases: [String]
    public init(_ name: String, cases: [String]) { self.name = name; self.cases = cases }
}

public struct XQInputObjectType: Equatable, Sendable {
    public var name: String
    public var fields: [XQArgument]
    public init(_ name: String, fields: [XQArgument]) { self.name = name; self.fields = fields }
}

public struct XQSchema: Equatable, Sendable {
    public var topLevel: [XQField]
    public var types: [XQObjectType]
    public var enums: [XQEnumType]
    public var inputs: [XQInputObjectType]
}
