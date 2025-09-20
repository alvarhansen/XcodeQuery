import XCTest
@preconcurrency import GraphQL
import NIO
import XcodeProj
@testable import XcodeQueryKit

final class BuildConfigurationsTests: XCTestCase {
    func testSchemaExposesBuildConfigurationsField() throws {
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let query = schema.queryType
        XCTAssertNotNil(query.fields["buildConfigurations"], "Query should expose buildConfigurations field")
    }

    func testResolverReturnsUniqueSortedConfigurations() throws {
        // Arrange
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "BuildConfigurationsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "No projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "BuildConfigurationsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "No projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // Act
        let result = try graphql(schema: schema, request: "{ buildConfigurations }", context: ctx, eventLoopGroup: group).wait()
        guard let arr = result.data?.dictionary?["buildConfigurations"]?.array else { XCTFail("No data"); return }
        let names = arr.compactMap { $0.string }

        // Assert: at least Debug/Release present, unique and sorted
        XCTAssertTrue(names.count >= 2, "Expected at least two configurations")
        let set = Set(names)
        XCTAssertEqual(set.count, names.count, "Expected unique configurations")
        XCTAssertTrue(set.isSuperset(of: ["Debug", "Release"]))
        XCTAssertEqual(names, names.sorted(), "Expected configurations sorted alphabetically")
    }
}

