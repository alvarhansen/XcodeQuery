import XCTest
@testable import XcodeQueryKit

final class SchemesSchemaTests: XCTestCase {
    func testSchemaIncludesSchemesTypesAndFields() throws {
        let schema = try XQGraphQLSchema.makeSchema()
        let query = schema.queryType
        XCTAssertNotNil(query.fields["schemes"])
        XCTAssertNotNil(schema.getType(name: "Scheme") as? GraphQLObjectType)
        XCTAssertNotNil(schema.getType(name: "SchemeRef") as? GraphQLObjectType)
        XCTAssertNotNil(schema.getType(name: "SchemeFilter") as? GraphQLInputObjectType)
    }
}

