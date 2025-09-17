import XCTest
@testable import XcodeQueryKit
import Darwin
import GraphQL
import NIO
import XcodeProj

final class GraphQLDualExecutionTests: XCTestCase {
    @MainActor
    func testLegacyVsGraphQLSwiftParity() throws {
        let cases: [(name: String, query: String)] = [
            ("targetsBasic", "targets { name type }"),
            ("flatSources", "targetSources(pathMode: NORMALIZED) { target path }"),
            ("nestedDeps", "targets(type: UNIT_TEST) { name dependencies(recursive: true) { name } }")
        ]

        let fixture = try GraphQLBaselineFixture()
        for c in cases {
            try XCTContext.runActivity(named: c.name) { _ in
                // Legacy output (baseline)
                let legacy = try fixture.evaluateToCanonicalJSON(query: c.query)

                // GraphQLSwift output via direct execution
                let swift = try Self.evaluateWithGraphQLSwiftCanonical(query: c.query, fixture: fixture)

                XCTAssertEqual(swift, legacy)
            }
        }
    }
    private static func evaluateWithGraphQLSwiftCanonical(query: String, fixture: GraphQLBaselineFixture) throws -> String {
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        // Get projectPath from fixture's projectQuery using reflection
        let mirror = Mirror(reflecting: fixture)
        guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
            throw NSError(domain: "GraphQLDualExecutionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to access projectQuery"])
        }
        let m = Mirror(reflecting: qp)
        guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
            throw NSError(domain: "GraphQLDualExecutionTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"])
        }
        let proj = try XcodeProj(pathString: projectPath)
        let ctx = XQGQLContext(project: proj, projectPath: projectPath)
        let request = "{" + query + "}"
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let result = try graphql(schema: schema, request: request, context: ctx, eventLoopGroup: group).wait()
        let dataMap = result.data ?? .dictionary([:])
        let jsonValue = Self.jsonValue(from: dataMap)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let out = try encoder.encode(jsonValue)
        var s = String(data: out, encoding: .utf8) ?? "{}"
        if !s.hasSuffix("\n") { s.append("\n") }
        return s
    }

    private static func jsonValue(from map: Map) -> JSONValue {
        switch map {
        case .undefined: return .null
        case .null: return .null
        case .bool(let b): return .bool(b)
        case .number(let n): return .number(n.doubleValue)
        case .string(let s): return .string(s)
        case .array(let arr): return .array(arr.map { jsonValue(from: $0) })
        case .dictionary(let dict):
            var out: [String: JSONValue] = [:]
            for (k, v) in dict { out[k] = jsonValue(from: v) }
            return .object(out)
        }
    }
}
