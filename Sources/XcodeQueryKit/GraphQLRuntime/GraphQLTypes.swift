import Foundation

public protocol GraphQLType {}
public protocol GraphQLNamedType: GraphQLType { var name: String { get } }
public protocol GraphQLInputType: GraphQLType {}

public typealias GraphQLFieldResolveInput = (Any, Map, Any, GraphQLResolveInfo) throws -> Any?

public struct GraphQLResolveInfo {
    public let fieldName: String
    public let parentType: GraphQLObjectType
}

public struct GraphQLArgument {
    public let type: GraphQLInputType
    public let defaultValue: Map?

    public init(type: GraphQLInputType, defaultValue: Map? = nil) {
        self.type = type
        self.defaultValue = defaultValue
    }
}

public struct GraphQLArgumentDefinition {
    public let name: String
    public let type: GraphQLInputType
    public let defaultValue: Map?
}

public struct GraphQLField {
    public let type: GraphQLType
    public let args: [GraphQLArgumentDefinition]
    public let resolve: GraphQLFieldResolveInput?

    public init(type: GraphQLType, args: [String: GraphQLArgument] = [:], resolve: GraphQLFieldResolveInput? = nil) {
        self.type = type
        self.resolve = resolve
        self.args = args.map { GraphQLArgumentDefinition(name: $0.key, type: $0.value.type, defaultValue: $0.value.defaultValue) }
            .sorted { $0.name < $1.name }
    }
}

public typealias GraphQLFieldDefinition = GraphQLField

public struct InputObjectField {
    public let type: GraphQLInputType
    public let defaultValue: Map?

    public init(type: GraphQLInputType, defaultValue: Map? = nil) {
        self.type = type
        self.defaultValue = defaultValue
    }
}

public struct GraphQLEnumValue {
    public let name: String
    public let value: Map?

    public init(value: Map? = nil) {
        self.name = ""
        self.value = value
    }

    public init(name: String, value: Map? = nil) {
        self.name = name
        self.value = value
    }
}

public final class GraphQLScalarType: GraphQLNamedType, GraphQLInputType, @unchecked Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
        GraphQLTypeRegistry.shared.register(self)
    }
}

public final class GraphQLEnumType: GraphQLNamedType, GraphQLInputType, @unchecked Sendable {
    public let name: String
    public let values: [GraphQLEnumValue]

    public init(name: String, values: [String: GraphQLEnumValue]) throws {
        self.name = name
        self.values = values.map { GraphQLEnumValue(name: $0.key, value: $0.value.value) }
        GraphQLTypeRegistry.shared.register(self)
    }
}

public final class GraphQLObjectType: GraphQLNamedType, @unchecked Sendable {
    public let name: String
    public let fields: [String: GraphQLField]

    public init(name: String, fields: [String: GraphQLField]) throws {
        self.name = name
        self.fields = fields
        GraphQLTypeRegistry.shared.register(self)
    }
}

public final class GraphQLInputObjectType: GraphQLNamedType, GraphQLInputType, @unchecked Sendable {
    public let name: String
    public let fields: [String: InputObjectField]

    public init(name: String, fields: [String: InputObjectField]) throws {
        self.name = name
        self.fields = fields
        GraphQLTypeRegistry.shared.register(self)
    }
}

public final class GraphQLList: GraphQLType, GraphQLInputType, @unchecked Sendable {
    public let ofType: GraphQLType

    public init(_ ofType: GraphQLType) {
        self.ofType = ofType
    }

    public convenience init(_ name: String) {
        self.init(GraphQLTypeReference(name: name))
    }
}

public final class GraphQLNonNull: GraphQLType, GraphQLInputType, @unchecked Sendable {
    public let ofType: GraphQLType

    public init(_ ofType: GraphQLType) {
        self.ofType = ofType
    }

    public convenience init(_ name: String) {
        self.init(GraphQLTypeReference(name: name))
    }
}

public final class GraphQLTypeReference: GraphQLNamedType, GraphQLInputType, @unchecked Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct GraphQLSchema {
    public let queryType: GraphQLObjectType
    public let typeMap: [String: GraphQLNamedType]

    public init(query: GraphQLObjectType) throws {
        self.queryType = query
        self.typeMap = GraphQLTypeRegistry.shared.snapshot(reachableFrom: query)
    }

    public func getType(name: String) -> GraphQLNamedType? {
        typeMap[name]
    }
}

public final class GraphQLTypeRegistry: @unchecked Sendable {
    public static let shared = GraphQLTypeRegistry()
    private var types: [String: GraphQLNamedType] = [:]

    public func register(_ type: GraphQLNamedType) {
        types[type.name] = type
    }

    public func resolve(_ name: String) -> GraphQLNamedType? {
        types[name]
    }

    public func snapshot(reachableFrom query: GraphQLObjectType) -> [String: GraphQLNamedType] {
        var visited: [String: GraphQLNamedType] = [:]
        func visitType(_ type: GraphQLType) {
            if let nn = type as? GraphQLNonNull { visitType(nn.ofType); return }
            if let list = type as? GraphQLList { visitType(list.ofType); return }
            if let named = type as? GraphQLNamedType {
                if visited[named.name] != nil { return }
                let resolved = (named is GraphQLTypeReference) ? (types[named.name] ?? named) : named
                visited[resolved.name] = resolved
                if let obj = resolved as? GraphQLObjectType {
                    for (_, field) in obj.fields { visitType(field.type); for arg in field.args { visitType(arg.type) } }
                } else if let input = resolved as? GraphQLInputObjectType {
                    for (_, field) in input.fields { visitType(field.type) }
                }
                return
            }
        }

        visitType(query)
        return visited
    }
}

public func getNamedType(type: GraphQLType) -> GraphQLNamedType? {
    if let nn = type as? GraphQLNonNull { return getNamedType(type: nn.ofType) }
    if let list = type as? GraphQLList { return getNamedType(type: list.ofType) }
    return type as? GraphQLNamedType
}

public let GraphQLString = GraphQLScalarType(name: "String")
public let GraphQLBoolean = GraphQLScalarType(name: "Boolean")
