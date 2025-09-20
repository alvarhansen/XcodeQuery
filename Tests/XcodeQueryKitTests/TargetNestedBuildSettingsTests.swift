import XCTest
@preconcurrency import GraphQL
import NIO
import XcodeProj
@testable import XcodeQueryKit

final class TargetNestedBuildSettingsTests: XCTestCase {
    func testSchemaTargetBuildSettingsFieldAndDefaults() throws {
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        guard let target = schema.getType(name: "Target") as? GraphQLObjectType else { return XCTFail("Missing Target type") }
        guard let field = target.fields["buildSettings"] else { return XCTFail("Missing Target.buildSettings field") }
        let args = Dictionary(uniqueKeysWithValues: field.args.map { ($0.name, $0) })
        XCTAssertEqual(args["scope"]?.defaultValue, Map("TARGET_ONLY"))
        XCTAssertNotNil(args["filter"])
        // Ensure BuildSetting object exists
        XCTAssertNotNil(schema.getType(name: "BuildSetting") as? GraphQLObjectType)
    }

    func testResolveNestedBuildSettingsScopes() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else { throw NSError(domain: "TNBS", code: 1) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else { throw NSError(domain: "TNBS", code: 2) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // TARGET_ONLY App SWIFT_VERSION Debug → 5.10 TARGET
        do {
            let q = #"{ target(name: "App") { buildSettings(scope: TARGET_ONLY, filter: { configuration: { eq: "Debug" }, key: { eq: "SWIFT_VERSION" } }) { configuration key value origin isArray } } }"#
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let arr = result.data?.dictionary?["target"]?.dictionary?["buildSettings"]?.array else { return XCTFail("No data") }
            XCTAssertEqual(arr.count, 1)
            let d = arr.first!.dictionary!
            XCTAssertEqual(d["configuration"]?.string, "Debug")
            XCTAssertEqual(d["key"]?.string, "SWIFT_VERSION")
            XCTAssertEqual(d["value"]?.string, "5.10")
            XCTAssertEqual(d["origin"]?.string, "TARGET")
            XCTAssertEqual(d["isArray"]?.bool, false)
        }

        // PROJECT_ONLY same → 5.9 PROJECT
        do {
            let q = #"{ target(name: "App") { buildSettings(scope: PROJECT_ONLY, filter: { configuration: { eq: "Debug" }, key: { eq: "SWIFT_VERSION" } }) { configuration key value origin } } }"#
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["target"]?.dictionary?["buildSettings"]?.array ?? []
            XCTAssertEqual(arr.count, 1)
            XCTAssertEqual(arr.first?.dictionary?["value"]?.string, "5.9")
            XCTAssertEqual(arr.first?.dictionary?["origin"]?.string, "PROJECT")
        }

        // Array normalization
        do {
            let q = #"{ target(name: "App") { buildSettings(scope: TARGET_ONLY, filter: { key: { eq: "SWIFT_ACTIVE_COMPILATION_CONDITIONS" } }) { key values isArray } } }"#
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["target"]?.dictionary?["buildSettings"]?.array ?? []
            XCTAssertFalse(arr.isEmpty)
            for v in arr { XCTAssertEqual(v.dictionary?["isArray"]?.bool, true); XCTAssertNotNil(v.dictionary?["values"]?.array) }
        }
    }
}

