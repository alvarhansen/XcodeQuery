import Foundation
import GraphQL

public enum XQSchemaBuilder {
    public static func fromGraphQLSwift() throws -> XQSchema {
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        return try fromGraphQLSchema(schema)
    }

    public static func fromGraphQLSchema(_ schema: GraphQLSchema) throws -> XQSchema {
        // Top-level fields from Query
        let topLevel: [XQField] = schema.queryType.fields.map { (name, def) in
            XQField(name, args: def.args.map { toXQArgument($0) }, type: toTypeRef(def.type))
        }

        // Object types (exclude Query and introspection)
        var objectTypes: [XQObjectType] = []
        for (_, t) in schema.typeMap {
            guard let obj = t as? GraphQLObjectType else { continue }
            guard !obj.name.hasPrefix("__"), obj.name != "Query" else { continue }
            let fields: [XQField] = obj.fields.map { (name, def) in
                XQField(name, args: def.args.map { toXQArgument($0) }, type: toTypeRef(def.type))
            }
            objectTypes.append(XQObjectType(obj.name, fields: fields))
        }
        objectTypes.sort { $0.name < $1.name }

        // Input object types
        var inputs: [XQInputObjectType] = []
        for (_, t) in schema.typeMap {
            guard let input = t as? GraphQLInputObjectType, !input.name.hasPrefix("__") else { continue }
            let fields: [XQArgument] = input.fields.map { (name, def) in
                let dv = formatDefault(def.defaultValue, forType: def.type, schema: schema)
                return XQArgument(name, toTypeRef(def.type), defaultValue: dv)
            }
            inputs.append(XQInputObjectType(input.name, fields: fields))
        }
        inputs.sort { $0.name < $1.name }

        // Enums
        var enums: [XQEnumType] = []
        for (_, t) in schema.typeMap {
            guard let en = t as? GraphQLEnumType, !en.name.hasPrefix("__") else { continue }
            let cases = en.values.map { $0.name }
            enums.append(XQEnumType(en.name, cases: cases))
        }
        enums.sort { $0.name < $1.name }

        return XQSchema(topLevel: topLevel, types: objectTypes, enums: enums, inputs: inputs)
    }

    // MARK: - Helpers
    private static func toXQArgument(_ arg: GraphQLArgumentDefinition) -> XQArgument {
        let def = formatDefault(arg.defaultValue, forType: arg.type, schema: nil)
        return XQArgument(arg.name, toTypeRef(arg.type), defaultValue: def)
    }

    private static func toTypeRef(_ type: GraphQLType) -> XQSTypeRef {
        // Handle NonNull(List(T)) and NonNull(Named)
        if let nn = type as? GraphQLNonNull {
            let inner = nn.ofType
            if let list = inner as? GraphQLList {
                let (elem, elemNN) = unpackListElement(list.ofType)
                return .list(of: elem, nonNull: true, elementNonNull: elemNN)
            } else if let named = getNamedType(type: inner) {
                return .named(named.name, nonNull: true)
            } else {
                // Fallback to recursion
                return forceNonNull(toTypeRef(inner))
            }
        }
        if let list = type as? GraphQLList {
            let (elem, elemNN) = unpackListElement(list.ofType)
            return .list(of: elem, nonNull: false, elementNonNull: elemNN)
        }
        if let named = getNamedType(type: type) {
            return .named(named.name, nonNull: false)
        }
        return .named("Unknown", nonNull: false)
    }

    private static func unpackListElement(_ t: GraphQLType) -> (XQSTypeRef, Bool) {
        if let nn = t as? GraphQLNonNull {
            if let named = getNamedType(type: nn.ofType) {
                return (.named(named.name, nonNull: false), true)
            }
            // Fallback to recursion for complex element types
            return (toTypeRef(nn.ofType), true)
        } else {
            if let named = getNamedType(type: t) {
                return (.named(named.name, nonNull: false), false)
            }
            return (toTypeRef(t), false)
        }
    }

    private static func forceNonNull(_ t: XQSTypeRef) -> XQSTypeRef {
        switch t {
        case .named(let n, _): return .named(n, nonNull: true)
        case .list(of: let inner, _, let elemNN): return .list(of: inner, nonNull: true, elementNonNull: elemNN)
        }
    }

    private static func isEnumType(_ t: GraphQLInputType, schema: GraphQLSchema?) -> Bool {
        guard let named = getNamedType(type: t) else { return false }
        return named is GraphQLEnumType
    }

    private static func formatDefault(_ map: Map?, forType: GraphQLInputType, schema: GraphQLSchema?) -> String? {
        guard let map else { return nil }
        if let b = map.bool { return b ? "true" : "false" }
        if let s = map.string {
            // If the target is an enum, surface without quotes
            if isEnumType(forType, schema: schema) { return s }
            // Otherwise, quote the string
            let escaped = s.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"" + escaped + "\""
        }
        if let i = map.int { return String(i) }
        if let d = map.double { return String(d) }
        // Fallback representation
        return String(describing: map)
    }
}
