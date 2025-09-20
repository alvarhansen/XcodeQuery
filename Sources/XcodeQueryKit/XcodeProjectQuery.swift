import Foundation
import XcodeProj
@preconcurrency import GraphQL
import NIO

public class XcodeProjectQuery {
    public enum Error: Swift.Error { case invalidQuery(String) }

    private let projectPath: String

    public init(projectPath: String) {
        self.projectPath = projectPath
    }

    // GraphQL-only entrypoint
    public func evaluate(query: String) throws -> AnyEncodable {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("{") else {
            throw Error.invalidQuery("Top-level braces are not supported. Write selection only, e.g., targets { name type }")
        }
        let value = try evaluateWithGraphQLSwift(selection: trimmed)
        return AnyEncodable(value)
    }

    // MARK: - GraphQLSwift execution path
    private func evaluateWithGraphQLSwift(selection: String) throws -> JSONValue {
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let proj = try XcodeProj(pathString: projectPath)
        let ctx = XQGQLContext(project: proj, projectPath: projectPath)
        let request = "{" + selection + "}"
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let result = try graphql(schema: schema, request: request, context: ctx, eventLoopGroup: group).wait()
        if !result.errors.isEmpty {
            let msg = result.errors.map { $0.message }.joined(separator: "; ")
            throw NSError(domain: "GraphQL", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        guard let data = result.data else { return .object([:]) }
        return JSONValue(fromMap: data)
    }
}

// Shared types used by GraphQL execution and encoding
struct Target: Codable, Equatable {
    var name: String
    var type: TargetType
}

struct SourceEntry: Codable, Equatable { var target: String; var path: String }
struct OwnerEntry: Codable, Equatable { var path: String; var targets: [String] }

struct BuildScriptEntry: Codable, Equatable {
    var target: String
    var name: String?
    var stage: Stage
    var inputPaths: [String]
    var outputPaths: [String]
    var inputFileListPaths: [String]
    var outputFileListPaths: [String]

    enum Stage: String, Codable { case pre, post }
}

struct ResourceEntry: Codable, Equatable { var target: String; var path: String }

enum TargetType: String, Codable, Equatable {
    case app
    case framework
    case staticLibrary
    case dynamicLibrary
    case unitTest
    case uiTest
    case extensionKit
    case bundle
    case commandLineTool
    case watchApp
    case watch2App
    case tvApp
    case other

    static func from(productType: PBXProductType?) -> TargetType {
        guard let productType else { return .other }
        switch productType {
        case .application: return .app
        case .framework: return .framework
        case .staticLibrary: return .staticLibrary
        case .dynamicLibrary: return .dynamicLibrary
        case .unitTestBundle: return .unitTest
        case .uiTestBundle: return .uiTest
        case .appExtension: return .extensionKit
        case .bundle: return .bundle
        case .commandLineTool: return .commandLineTool
        case .watchApp: return .watchApp
        case .watch2App: return .watch2App
        default: return .other
        }
    }
}

public struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    public init<T: Encodable>(_ wrapped: T) { self._encode = wrapped.encode }
    public func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

// MARK: - Map to JSONValue bridging
extension JSONValue {
    init(fromMap map: Map) {
        switch map {
        case .undefined:
            self = .null
        case .null:
            self = .null
        case .bool(let b):
            self = .bool(b)
        case .number(let num):
            self = .number(num.doubleValue)
        case .string(let s):
            self = .string(s)
        case .array(let arr):
            self = .array(arr.map { JSONValue(fromMap: $0) })
        case .dictionary(let dict):
            var out: [String: JSONValue] = [:]
            out.reserveCapacity(dict.count)
            for (k, v) in dict { out[k] = JSONValue(fromMap: v) }
            self = .object(out)
        }
    }
}
