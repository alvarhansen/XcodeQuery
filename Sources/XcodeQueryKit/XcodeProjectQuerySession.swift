import Foundation
import XcodeProj
import GraphQL
import NIO

public final class XcodeProjectQuerySession {
    public enum Error: Swift.Error { case invalidQuery(String) }

    private let projectPath: String
    private let project: XcodeProj
    private let executor: GraphQLExecutor

    public init(projectPath: String) throws {
        self.projectPath = projectPath
        self.project = try XcodeProj(pathString: projectPath)
        self.executor = GraphQLExecutor(project: project, projectPath: projectPath)
    }

    public func evaluate(query: String) throws -> AnyEncodable {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("{") else {
            throw Error.invalidQuery("Top-level braces are not supported. Write selection only, e.g., targets { name type }")
        }
        // Feature flag: default is GraphQLSwift when set (CLI flips this by default)
        if let cstr = getenv("XCQ_USE_GRAPHQLSWIFT"), String(cString: cstr) == "1" {
            let swift = try evaluateWithGraphQLSwift(selection: trimmed)
            return AnyEncodable(swift)
        }
        let value = try GraphQL.parseAndExecute(query: trimmed, with: executor)
        return AnyEncodable(value)
    }

    private func evaluateWithGraphQLSwift(selection: String) throws -> JSONValue {
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let ctx = XQGQLContext(project: project, projectPath: projectPath)
        let request = "{" + selection + "}"
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let result = try graphql(schema: schema, request: request, context: ctx, eventLoopGroup: group).wait()
        guard let data = result.data else { return .object([:]) }
        return JSONValue(fromMap: data)
    }
}
