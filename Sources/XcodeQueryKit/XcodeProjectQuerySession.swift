import Foundation
import XcodeProj
@preconcurrency import GraphQL
import NIO

public final class XcodeProjectQuerySession {
    public enum Error: Swift.Error { case invalidQuery(String) }

    private let projectPath: String
    private let project: XcodeProj

    public init(projectPath: String) throws {
        self.projectPath = projectPath
        self.project = try XcodeProj(pathString: projectPath)
    }

    public func evaluate(query: String) throws -> AnyEncodable {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("{") else {
            throw Error.invalidQuery("Top-level braces are not supported. Write selection only, e.g., targets { name type }")
        }
        // GraphQLSwift-only execution
        let swift = try evaluateWithGraphQLSwift(selection: trimmed)
        return AnyEncodable(swift)
    }

    private func evaluateWithGraphQLSwift(selection: String) throws -> JSONValue {
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let ctx = XQGQLContext(project: project, projectPath: projectPath)
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
