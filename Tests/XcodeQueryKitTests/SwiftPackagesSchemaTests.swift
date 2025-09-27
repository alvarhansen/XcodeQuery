import XCTest
@testable import XcodeQueryKit
@preconcurrency import GraphQL

final class SwiftPackagesSchemaTests: XCTestCase {
    func testSchemaIncludesSwiftPackagesTypesAndFields() throws {
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let query = schema.queryType

        // Top-level fields
        XCTAssertNotNil(query.fields["swiftPackages"])
        XCTAssertNotNil(query.fields["targetPackageProducts"])

        // Target field
        guard let target = schema.getType(name: "Target") as? GraphQLObjectType else { return XCTFail("Missing Target type") }
        XCTAssertNotNil(target.fields["packageProducts"])

        // Types
        XCTAssertNotNil(schema.getType(name: "SwiftPackage") as? GraphQLObjectType)
        XCTAssertNotNil(schema.getType(name: "PackageRequirement") as? GraphQLObjectType)
        XCTAssertNotNil(schema.getType(name: "PackageProduct") as? GraphQLObjectType)
        XCTAssertNotNil(schema.getType(name: "PackageConsumer") as? GraphQLObjectType)
        XCTAssertNotNil(schema.getType(name: "PackageProductUsage") as? GraphQLObjectType)

        // Inputs
        XCTAssertNotNil(schema.getType(name: "SwiftPackageFilter") as? GraphQLInputObjectType)
        XCTAssertNotNil(schema.getType(name: "PackageProductFilter") as? GraphQLInputObjectType)
        XCTAssertNotNil(schema.getType(name: "PackageProductUsageFilter") as? GraphQLInputObjectType)

        // Enums
        XCTAssertNotNil(schema.getType(name: "RequirementKind") as? GraphQLEnumType)
        XCTAssertNotNil(schema.getType(name: "PackageProductType") as? GraphQLEnumType)
    }
}

