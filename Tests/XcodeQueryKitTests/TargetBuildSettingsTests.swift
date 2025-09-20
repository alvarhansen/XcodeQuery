import XCTest
@preconcurrency import GraphQL
import NIO
import XcodeProj
@testable import XcodeQueryKit

final class TargetBuildSettingsTests: XCTestCase {
    func testSchemaIncludesTargetBuildSettingsEnumsAndDefaults() throws {
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let query = schema.queryType
        guard let field = query.fields["targetBuildSettings"] else { return XCTFail("Missing targetBuildSettings field") }
        let args = Dictionary(uniqueKeysWithValues: field.args.map { ($0.name, $0) })
        XCTAssertNotNil(args["scope"])
        XCTAssertNotNil(args["filter"])
        // Default scope should be TARGET_ONLY
        XCTAssertEqual(args["scope"]?.defaultValue, Map("TARGET_ONLY"))
        // Enums exist
        XCTAssertNotNil(schema.getType(name: "BuildSettingsScope") as? GraphQLEnumType)
        XCTAssertNotNil(schema.getType(name: "BuildSettingOrigin") as? GraphQLEnumType)
        // Input exists and has expected keys
        guard let input = schema.getType(name: "BuildSettingFilter") as? GraphQLInputObjectType else { return XCTFail("Missing BuildSettingFilter") }
        let keys = Set(input.fields.keys)
        XCTAssertTrue(keys.isSuperset(of: ["key", "configuration", "target"]))
        // Object exists
        XCTAssertNotNil(schema.getType(name: "TargetBuildSetting") as? GraphQLObjectType)
    }

    func testTargetBuildSettingsScopeAndFilters() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "TargetBuildSettingsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "No projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "TargetBuildSettingsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "No projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // TARGET_ONLY filtered to App + SWIFT_VERSION + Debug
        do {
            let q = #"{ targetBuildSettings(scope: TARGET_ONLY, filter: { target: { eq: "App" }, key: { eq: "SWIFT_VERSION" }, configuration: { eq: "Debug" } }) { target configuration key value isArray origin } }"#
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["targetBuildSettings"]?.array ?? []
            XCTAssertEqual(arr.count, 1)
            let d = arr.first?.dictionary ?? [:]
            XCTAssertEqual(d["target"]?.string, "App")
            XCTAssertEqual(d["configuration"]?.string, "Debug")
            XCTAssertEqual(d["key"]?.string, "SWIFT_VERSION")
            XCTAssertEqual(d["value"]?.string, "5.10")
            XCTAssertEqual(d["origin"]?.string, "TARGET")
            XCTAssertEqual(d["isArray"]?.bool, false)
        }

        // PROJECT_ONLY for same filter should yield project value and origin PROJECT
        do {
            let q = #"{ targetBuildSettings(scope: PROJECT_ONLY, filter: { target: { eq: "App" }, key: { eq: "SWIFT_VERSION" }, configuration: { eq: "Debug" } }) { target configuration key value origin } }"#
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["targetBuildSettings"]?.array ?? []
            // PROJECT_ONLY duplicates rows per target; still 1 for this precise filter
            XCTAssertEqual(arr.count, 1)
            let d = arr.first?.dictionary ?? [:]
            XCTAssertEqual(d["origin"]?.string, "PROJECT")
            XCTAssertEqual(d["value"]?.string, "5.9")
        }

        // MERGED: App SWIFT_VERSION should come from TARGET; Lib should come from PROJECT
        do {
            let q = #"{ targetBuildSettings(scope: MERGED, filter: { key: { eq: "SWIFT_VERSION" }, configuration: { eq: "Debug" } }) { target origin value } }"#
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["targetBuildSettings"]?.array ?? []
            // Build mapping target->(origin, value)
            var map: [String: (String, String)] = [:]
            for v in arr {
                if let d = v.dictionary, let t = d["target"]?.string, let o = d["origin"]?.string, let val = d["value"]?.string {
                    map[t] = (o, val)
                }
            }
            XCTAssertEqual(map["App"]?.0, "TARGET")
            XCTAssertEqual(map["App"]?.1, "5.10")
            XCTAssertEqual(map["Lib"]?.0, "PROJECT")
            XCTAssertEqual(map["Lib"]?.1, "5.9")
        }

        // Array normalization: TARGET_ONLY fetch conditions array for App
        do {
            let q = #"{ targetBuildSettings(scope: TARGET_ONLY, filter: { target: { eq: "App" }, key: { eq: "SWIFT_ACTIVE_COMPILATION_CONDITIONS" } }) { values isArray } }"#
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["targetBuildSettings"]?.array ?? []
            XCTAssertFalse(arr.isEmpty)
            for v in arr { XCTAssertEqual(v.dictionary?["isArray"]?.bool, true); XCTAssertNotNil(v.dictionary?["values"]?.array) }
        }
    }
}

