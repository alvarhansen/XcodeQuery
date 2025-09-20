import XCTest
@preconcurrency import GraphQL
import NIO
import XcodeProj
@testable import XcodeQueryKit

final class ProjectBuildSettingsTests: XCTestCase {
    func testSchemaIncludesProjectBuildSettingsAndFilter() throws {
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let query = schema.queryType
        guard let field = query.fields["projectBuildSettings"] else { return XCTFail("Missing projectBuildSettings field") }
        // One arg: filter
        XCTAssertEqual(field.args.count, 1)
        XCTAssertEqual(field.args.first?.name, "filter")
        // Input type exists with keys
        guard let input = schema.getType(name: "ProjectBuildSettingFilter") as? GraphQLInputObjectType else {
            return XCTFail("Missing ProjectBuildSettingFilter input")
        }
        let keys = Set(input.fields.keys)
        XCTAssertTrue(keys.isSuperset(of: ["key", "configuration"]))
        // Object type exists with expected fields
        XCTAssertNotNil(schema.getType(name: "ProjectBuildSetting") as? GraphQLObjectType)
    }

    func testProjectBuildSettingsAllConfigsAndFilter() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "ProjectBuildSettingsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "No projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "ProjectBuildSettingsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "No projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // No filter: expect rows across both Debug and Release
        do {
            let result = try graphql(schema: schema, request: "{ projectBuildSettings { configuration key value values isArray } }", context: ctx, eventLoopGroup: group).wait()
            guard let arr = result.data?.dictionary?["projectBuildSettings"]?.array else { return XCTFail("No data") }
            XCTAssertFalse(arr.isEmpty, "Expected some project build settings")
            // Sorted by configuration then key
            var prev: (String, String)? = nil
            for v in arr {
                guard let d = v.dictionary, let c = d["configuration"]?.string, let k = d["key"]?.string else { continue }
                if let p = prev {
                    if c == p.0 { XCTAssertTrue(k >= p.1) } else { XCTAssertTrue(c >= p.0) }
                }
                prev = (c, k)
                // Normalization invariant
                let isArray = d["isArray"]?.bool ?? false
                if isArray {
                    XCTAssertNil(d["value"]?.string)
                    XCTAssertNotNil(d["values"]?.array)
                } else {
                    XCTAssertNotNil(d["value"]?.string)
                }
            }
        }

        // Filter by configuration Debug
        do {
            let q = #"{ projectBuildSettings(filter: { configuration: { eq: "Debug" } }) { configuration } }"#
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["projectBuildSettings"]?.array ?? []
            for v in arr { XCTAssertEqual(v.dictionary?["configuration"]?.string, "Debug") }
        }

        // Filter by key prefix SWIFT; should include our injected SWIFT_VERSION or SWIFT_ACTIVE_COMPILATION_CONDITIONS
        do {
            let q = #"{ projectBuildSettings(filter: { key: { prefix: "SWIFT" } }) { key } }"#
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["projectBuildSettings"]?.array ?? []
            XCTAssertTrue(arr.allSatisfy { ($0.dictionary?["key"]?.string ?? "").hasPrefix("SWIFT") })
        }
    }
}

