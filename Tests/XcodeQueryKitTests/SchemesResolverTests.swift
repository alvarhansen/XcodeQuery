import XCTest
@preconcurrency import GraphQL
import NIO
@testable import XcodeQueryKit

final class SchemesResolverTests: XCTestCase {
    func testListSchemesAndFilters() throws {
        let fx = try SchemesFixture()
        let ctx = try fx.makeContext()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        // List schemes with refs
        do {
            let q = "{ schemes { name isShared buildTargets { name } testTargets { name } runTarget { name } } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let arr = result.data?.dictionary?["schemes"]?.array else { XCTFail("No data"); return }
            let names = arr.compactMap { $0.dictionary?["name"]?.string }
            XCTAssertEqual(names.sorted(), ["AppScheme", "LibScheme"]) 
            // AppScheme specifics
            let app = arr.first { $0.dictionary?["name"]?.string == "AppScheme" }?.dictionary
            XCTAssertEqual(Set(app?["buildTargets"]?.array?.compactMap { $0.dictionary?["name"]?.string } ?? []), ["App", "Lib"])
            XCTAssertEqual(Set(app?["testTargets"]?.array?.compactMap { $0.dictionary?["name"]?.string } ?? []), ["AppTests"])
            XCTAssertEqual(app?["runTarget"]?.dictionary?["name"]?.string, "App")
        }

        // Filter schemes by name prefix
        do {
            let q = "{ schemes(filter: { name: { prefix: \"Lib\" } }) { name } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["schemes"]?.array ?? []
            XCTAssertEqual(arr.count, 1)
            XCTAssertEqual(arr.first?.dictionary?["name"]?.string, "LibScheme")
        }

        // Filter schemes that include target App
        do {
            let q = "{ schemes(filter: { includesTarget: { eq: \"App\" } }) { name } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["schemes"]?.array ?? []
            let names = Set(arr.compactMap { $0.dictionary?["name"]?.string })
            XCTAssertTrue(names.contains("AppScheme"))
            XCTAssertFalse(names.contains("LibScheme"))
        }
    }
}

