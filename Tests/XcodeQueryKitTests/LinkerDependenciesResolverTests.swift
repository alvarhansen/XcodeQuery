import XCTest
@preconcurrency import GraphQL
import NIO
import XcodeProj
@testable import XcodeQueryKit

final class LinkerDependenciesResolverTests: XCTestCase {
    func testNestedAndFlatLinkDependencies() throws {
        let fixture = try LinkerDependenciesFixture()

        // Build schema and context
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "LinkerDependenciesResolverTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "LinkerDependenciesResolverTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "No projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // Nested per-target
        do {
            let q = "{ target(name: \"App\") { linkDependencies(pathMode: NORMALIZED) { name kind path embed weak } } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let arr = result.data?.dictionary?["target"]?.dictionary?["linkDependencies"]?.array else { XCTFail("No data"); return }
            // Local.framework: kind FRAMEWORK, embed true, has path
            XCTAssertTrue(arr.contains { v in
                guard let d = v.dictionary else { return false }
                let name = d["name"]?.string
                let kind = d["kind"]?.string
                let embed = d["embed"]?.bool ?? false
                let path = d["path"]?.string ?? ""
                return name == "Local.framework" && kind == "FRAMEWORK" && embed && path.contains("Vendor/Local.framework")
            })
            // UIKit.framework: SDK_FRAMEWORK, no path, weak linking allowed
            XCTAssertTrue(arr.contains { v in
                guard let d = v.dictionary else { return false }
                let name = d["name"]?.string
                let kind = d["kind"]?.string
                let path = d["path"]
                return name == "UIKit.framework" && kind == "SDK_FRAMEWORK" && (path == nil || path!.isNull)
            })
            // Package product ACore
            XCTAssertTrue(arr.contains { v in
                guard let d = v.dictionary else { return false }
                return d["name"]?.string == "ACore" && d["kind"]?.string == "PACKAGE_PRODUCT"
            })
        }

        // Flat view filtered by target
        do {
            let q = "{ targetLinkDependencies(filter: { target: { eq: \"App\" } }) { target name kind embed } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let arr = result.data?.dictionary?["targetLinkDependencies"]?.array else { XCTFail("No data"); return }
            XCTAssertTrue(arr.contains { v in v.dictionary?["name"]?.string == "Local.framework" && v.dictionary?["kind"]?.string == "FRAMEWORK" && v.dictionary?["embed"]?.bool == true })
            XCTAssertTrue(arr.contains { v in v.dictionary?["name"]?.string == "ACore" && v.dictionary?["kind"]?.string == "PACKAGE_PRODUCT" })
        }
    }
}

