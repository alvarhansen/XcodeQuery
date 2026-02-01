import Foundation

public struct GraphQLError: Error, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct GraphQLResult {
    public let data: Map?
    public let errors: [GraphQLError]
}

public struct GraphQLResultFuture {
    private let result: GraphQLResult

    init(_ result: GraphQLResult) {
        self.result = result
    }

    public func wait() throws -> GraphQLResult {
        return result
    }
}

public protocol EventLoopGroup {
    func syncShutdownGracefully() throws
}

public final class MultiThreadedEventLoopGroup: EventLoopGroup {
    public init(numberOfThreads: Int) {}
    public func syncShutdownGracefully() throws {}
}

public func graphql(schema: GraphQLSchema, request: String, context: Any, eventLoopGroup: EventLoopGroup) -> GraphQLResultFuture {
    do {
        var parser = GQLParser(request)
        let selections = try parser.parseDocument()
        let result = try GraphQLExecutor(schema: schema, context: context).execute(selections: selections)
        return GraphQLResultFuture(result)
    } catch let error as GQLParseError {
        return GraphQLResultFuture(GraphQLResult(data: nil, errors: [GraphQLError(message: error.formatted)]))
    } catch let error as GraphQLError {
        return GraphQLResultFuture(GraphQLResult(data: nil, errors: [error]))
    } catch {
        return GraphQLResultFuture(GraphQLResult(data: nil, errors: [GraphQLError(message: String(describing: error))]))
    }
}

private struct GraphQLExecutor {
    let schema: GraphQLSchema
    let context: Any

    func execute(selections: [GQLSelection]) throws -> GraphQLResult {
        var errors: [GraphQLError] = []
        let data = try executeSelections(selections, source: (), type: schema.queryType, errors: &errors)
        return GraphQLResult(data: data, errors: errors)
    }

    private func executeSelections(_ selections: [GQLSelection], source: Any, type: GraphQLObjectType, errors: inout [GraphQLError]) throws -> Map {
        var out: [String: Map] = [:]
        for sel in selections {
            guard let field = type.fields[sel.name] else {
                errors.append(GraphQLError(message: "Cannot query field \"\(sel.name)\" on type \"\(type.name)\"."))
                out[sel.name] = .null
                continue
            }
            do {
                let args = try coerceArguments(field.args, provided: sel.arguments, fieldName: sel.name)
                let info = GraphQLResolveInfo(fieldName: sel.name, parentType: type)
                let resolved = try field.resolve?(source, .dictionary(args), context, info)
                let completed = try completeValue(type: field.type, value: resolved, selectionSet: sel.selectionSet, fieldName: sel.name, errors: &errors)
                out[sel.name] = completed
            } catch let error as GraphQLError {
                errors.append(error)
                out[sel.name] = .null
            }
        }
        return .dictionary(out)
    }

    private func coerceArguments(_ defs: [GraphQLArgumentDefinition], provided: [String: Map], fieldName: String) throws -> [String: Map] {
        var out: [String: Map] = [:]
        for def in defs {
            if let value = provided[def.name] {
                out[def.name] = value
                continue
            }
            if let defaultValue = def.defaultValue {
                out[def.name] = defaultValue
                continue
            }
            if isNonNull(def.type) {
                throw GraphQLError(message: "Field \"\(fieldName)\" argument \"\(def.name)\" is required.")
            }
            out[def.name] = .undefined
        }
        return out
    }

    private func completeValue(type: GraphQLType, value: Any?, selectionSet: [GQLSelection]?, fieldName: String, errors: inout [GraphQLError]) throws -> Map {
        if let nonNull = type as? GraphQLNonNull {
            let completed = try completeValue(type: nonNull.ofType, value: value, selectionSet: selectionSet, fieldName: fieldName, errors: &errors)
            if case .null = completed {
                throw GraphQLError(message: "Non-null field \"\(fieldName)\" resolved to null.")
            }
            return completed
        }
        if let list = type as? GraphQLList {
            if selectionSet == nil && requiresSelection(list.ofType) {
                throw GraphQLError(message: "Field \"\(fieldName)\" of type \"\(renderType(type))\" must have a selection of subfields.")
            }
            guard let items = asAnyArray(value) else { return .array([]) }
            let completed = try items.map { try completeValue(type: list.ofType, value: $0, selectionSet: selectionSet, fieldName: fieldName, errors: &errors) }
            return .array(completed)
        }
        if let named = resolveNamed(type) {
            if let obj = named as? GraphQLObjectType {
                guard let selectionSet else {
                    throw GraphQLError(message: "Field \"\(fieldName)\" of type \"\(renderType(type))\" must have a selection of subfields.")
                }
                guard let resolved = value else { return .null }
                return try executeSelections(selectionSet, source: resolved, type: obj, errors: &errors)
            }
        }
        if selectionSet != nil {
            throw GraphQLError(message: "Field \"\(fieldName)\" must not have a selection since type \"\(renderType(type))\" has no subfields.")
        }
        return coerceScalar(value)
    }

    private func resolveNamed(_ type: GraphQLType) -> GraphQLNamedType? {
        if let nn = type as? GraphQLNonNull { return resolveNamed(nn.ofType) }
        if let list = type as? GraphQLList { return resolveNamed(list.ofType) }
        if let named = type as? GraphQLNamedType {
            if let ref = named as? GraphQLTypeReference {
                return GraphQLTypeRegistry.shared.resolve(ref.name) ?? ref
            }
            return named
        }
        return nil
    }

    private func requiresSelection(_ type: GraphQLType) -> Bool {
        guard let named = resolveNamed(type) else { return false }
        return named is GraphQLObjectType
    }

    private func isNonNull(_ type: GraphQLInputType) -> Bool {
        return type is GraphQLNonNull
    }

    private func coerceScalar(_ value: Any?) -> Map {
        guard let value else { return .null }
        if let map = value as? Map { return map }
        if let s = value as? String { return .string(s) }
        if let b = value as? Bool { return .bool(b) }
        if let i = value as? Int { return .number(Double(i)) }
        if let d = value as? Double { return .number(d) }
        if let f = value as? Float { return .number(Double(f)) }
        if let arr = asAnyArray(value) { return .array(arr.map { coerceScalar($0) }) }
        return .string(String(describing: value))
    }

    private func asAnyArray(_ value: Any?) -> [Any]? {
        guard let value else { return nil }
        if let arr = value as? [Any] { return arr }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .collection else { return nil }
        return mirror.children.map { $0.value }
    }

    private func renderType(_ type: GraphQLType) -> String {
        if let nn = type as? GraphQLNonNull { return renderType(nn.ofType) + "!" }
        if let list = type as? GraphQLList { return "[" + renderType(list.ofType) + "]" }
        if let named = resolveNamed(type) { return named.name }
        return "Unknown"
    }
}
