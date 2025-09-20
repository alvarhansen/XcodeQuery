import XCTest
@testable import XcodeQueryKit
@preconcurrency import GraphQL

final class GraphQLSwiftSchemaTests: XCTestCase {
    func testRootFieldsAndArgsMatchBaseline() throws {
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let query = schema.queryType

        func field(_ name: String) -> GraphQLFieldDefinition? { query.fields[name] }

        // targets(type, filter)
        if let f = field("targets") {
            XCTAssertNotNil(f.type as? GraphQLNonNull)
            XCTAssertEqual(Set(f.args.map { $0.name }), ["type", "filter"])
        } else { XCTFail("Missing field targets") }

        // target(name!)
        if let f = field("target") {
            XCTAssertEqual(f.args.first?.name, "name")
            if let nonNull = f.args.first?.type as? GraphQLNonNull, nonNull.ofType is GraphQLScalarType {
                // ok
            } else {
                XCTFail("target.name should be NonNull(String)")
            }
        } else { XCTFail("Missing field target") }

        // dependencies(name!, recursive=false, filter)
        if let f = field("dependencies") {
            XCTAssertEqual(Set(f.args.map { $0.name }), ["name", "recursive", "filter"])
            let recursiveDefault = f.args.first(where: { $0.name == "recursive" })?.defaultValue
            XCTAssertEqual(recursiveDefault, Map(false))
        } else { XCTFail("Missing field dependencies") }

        // dependents(name!, recursive=false, filter)
        if let f = field("dependents") {
            XCTAssertEqual(Set(f.args.map { $0.name }), ["name", "recursive", "filter"])
            let recursiveDefault = f.args.first(where: { $0.name == "recursive" })?.defaultValue
            XCTAssertEqual(recursiveDefault, Map(false))
        } else { XCTFail("Missing field dependents") }

        // targetSources(pathMode=FILE_REF, filter)
        if let f = field("targetSources") {
            let pm = f.args.first(where: { $0.name == "pathMode" })
            XCTAssertEqual(pm?.defaultValue, Map("FILE_REF"))
        } else { XCTFail("Missing field targetSources") }

        // targetResources(pathMode=FILE_REF, filter)
        if let f = field("targetResources") {
            let pm = f.args.first(where: { $0.name == "pathMode" })
            XCTAssertEqual(pm?.defaultValue, Map("FILE_REF"))
        } else { XCTFail("Missing field targetResources") }

        // targetDependencies(recursive=false, filter)
        if let f = field("targetDependencies") {
            let rec = f.args.first(where: { $0.name == "recursive" })
            XCTAssertEqual(rec?.defaultValue, Map(false))
        } else { XCTFail("Missing field targetDependencies") }

        // targetBuildScripts(filter)
        XCTAssertNotNil(field("targetBuildScripts"))

        // targetMembership(path!, pathMode=FILE_REF)
        if let f = field("targetMembership") {
            XCTAssertEqual(Set(f.args.map { $0.name }), ["path", "pathMode"])
            let pm = f.args.first(where: { $0.name == "pathMode" })
            XCTAssertEqual(pm?.defaultValue, Map("FILE_REF"))
        } else { XCTFail("Missing field targetMembership") }
    }

    func testEnumAndInputTypesExist() throws {
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        // Enums
        XCTAssertNotNil(schema.getType(name: "TargetType") as? GraphQLEnumType)
        XCTAssertNotNil(schema.getType(name: "PathMode") as? GraphQLEnumType)
        XCTAssertNotNil(schema.getType(name: "ScriptStage") as? GraphQLEnumType)
        // Inputs
        XCTAssertNotNil(schema.getType(name: "StringMatch") as? GraphQLInputObjectType)
        XCTAssertNotNil(schema.getType(name: "TargetFilter") as? GraphQLInputObjectType)
        XCTAssertNotNil(schema.getType(name: "SourceFilter") as? GraphQLInputObjectType)
        XCTAssertNotNil(schema.getType(name: "ResourceFilter") as? GraphQLInputObjectType)
        XCTAssertNotNil(schema.getType(name: "BuildScriptFilter") as? GraphQLInputObjectType)
    }
}
