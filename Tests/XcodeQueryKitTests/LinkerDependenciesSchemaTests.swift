import XCTest
@preconcurrency import GraphQL
@testable import XcodeQueryKit

final class LinkerDependenciesSchemaTests: XCTestCase {
    func testSchemaIncludesLinkerDependenciesTypesAndFields() throws {
        let schema = try XQGraphQLSwiftSchema.makeSchema()

        // Enums and inputs
        XCTAssertNotNil(schema.getType(name: "LinkKind") as? GraphQLEnumType)
        XCTAssertNotNil(schema.getType(name: "LinkFilter") as? GraphQLInputObjectType)

        // Object types
        XCTAssertNotNil(schema.getType(name: "LinkDependency") as? GraphQLObjectType)
        XCTAssertNotNil(schema.getType(name: "TargetLinkDependency") as? GraphQLObjectType)

        // Target field
        let target = try XCTUnwrap(schema.getType(name: "Target") as? GraphQLObjectType)
        XCTAssertNotNil(target.fields["linkDependencies"])

        // Root field
        let query = schema.queryType
        XCTAssertNotNil(query.fields["targetLinkDependencies"])
    }
}

