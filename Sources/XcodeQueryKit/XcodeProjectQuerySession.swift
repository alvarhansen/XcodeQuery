import Foundation
import XcodeProj

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
        let value = try GraphQL.parseAndExecute(query: trimmed, with: executor)
        return AnyEncodable(value)
    }
}

