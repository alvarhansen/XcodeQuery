import XCTest
import GraphQL
import NIO
import XcodeProj
import PathKit
import ProjectSpec
import XcodeGenKit
@testable import XcodeQueryKit

final class GraphQLSwiftResolverTests: XCTestCase {
    func testTargetsAndSourcesViaGraphQLSwift() throws {
        // Arrange project via baseline fixture
        let fixture = try GraphQLBaselineFixture()

        // Obtain schema and run query
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        // Extract context from fixture by reflection
        // NOTE: GraphQLBaselineFixture holds an XcodeProjectQuery; we re-create context by looking up its project path
        let mirror = Mirror(reflecting: fixture)
        guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
            XCTFail("Could not access projectQuery from fixture"); return
        }

        // We need XcodeProj to build context; re-open via known API
        let ctx: XQGQLContext = try {
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"])
            }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // Query 1: targets { name type }
        do {
            let result = try graphql(schema: schema, request: "{ targets { name type } }", context: ctx, eventLoopGroup: group).wait()
            guard let data = result.data?.dictionary, let arr = data["targets"]?.array else { XCTFail("No data"); return }
            let names = Set(arr.compactMap { $0.dictionary?["name"]?.string })
            XCTAssertEqual(names, ["App", "AppTests", "Lib"])
        }

        // Query 2: targetSources normalized
        do {
            let result = try graphql(schema: schema, request: "{ targetSources(pathMode: NORMALIZED) { target path } }", context: ctx, eventLoopGroup: group).wait()
            guard let data = result.data?.dictionary, let arr = data["targetSources"]?.array else { XCTFail("No data"); return }
            let found = arr.contains { row in
                if let d = row.dictionary, let t = d["target"]?.string, let p = d["path"]?.string {
                    return t == "Lib" && p.contains("Lib/Sources/LibFile.swift")
                }
                return false
            }
            XCTAssertTrue(found)
        }

        // Query 3: nested dependencies
        do {
            let q = "{ targets(type: UNIT_TEST) { name dependencies(recursive: true) { name } } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let data = result.data?.dictionary, let arr = data["targets"]?.array else { XCTFail("No data"); return }
            var deps = Set<String>()
            for tval in arr {
                if let d = tval.dictionary, let ds = d["dependencies"]?.array {
                    for dep in ds { if let name = dep.dictionary?["name"]?.string { deps.insert(name) } }
                }
            }
            XCTAssertEqual(deps, ["App", "Lib"])
        }
    }

    func testNestedSourcesFilterContainsDot() throws {
        // Arrange project via baseline fixture
        let fixture = try GraphQLBaselineFixture()

        // Obtain schema and run query
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        // Build context from fixture
        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not access projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // Query: nested sources with contains "." should match files with extensions
        let query = "{ targets { sources(filter: { path: { contains: \".\" } }) { path } } }"
        let result = try graphql(schema: schema, request: query, context: ctx, eventLoopGroup: group).wait()
        guard let data = result.data?.dictionary, let arr = data["targets"]?.array else { XCTFail("No data"); return }
        // Ensure at least one target reports at least one source
        let nonEmpty = arr.contains { tval in
            if let d = tval.dictionary, let srcs = d["sources"]?.array { return !srcs.isEmpty }
            return false
        }
        XCTAssertTrue(nonEmpty, "Expected some sources when filtering by contains '.'")
    }
}
