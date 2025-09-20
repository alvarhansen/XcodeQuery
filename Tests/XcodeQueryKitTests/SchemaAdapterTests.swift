import XCTest
@testable import XcodeQueryKit

final class SchemaAdapterTests: XCTestCase {
    func testTopLevelFieldNamesMatchStaticModel() throws {
        let built = try XQSchemaBuilder.fromGraphQLSwift()
        let gql = try XQGraphQLSwiftSchema.makeSchema()
        let gqlTop = Set(gql.queryType.fields.map { (k, _) in k })
        XCTAssertEqual(Set(built.topLevel.map { $0.name }), gqlTop)
    }

    func testRepresentativeDefaultsAndTypes() throws {
        let schema = try XQSchemaBuilder.fromGraphQLSwift()
        func field(_ name: String) -> XQField? { schema.topLevel.first { $0.name == name } }

        // dependencies(name!, recursive=false, filter): [Target!]!
        if let deps = field("dependencies") {
            XCTAssertEqual(deps.type, .listNN("Target"))
            let names = Set(deps.args.map { $0.name })
            XCTAssertEqual(names, ["name", "recursive", "filter"])
            let recursive = deps.args.first { $0.name == "recursive" }
            XCTAssertEqual(recursive?.defaultValue, "false")
        } else { XCTFail("Missing dependencies") }

        // targetSources(pathMode=FILE_REF): [TargetSource!]!
        if let ts = field("targetSources") {
            let pm = ts.args.first { $0.name == "pathMode" }
            XCTAssertEqual(pm?.defaultValue, "FILE_REF")
            XCTAssertEqual(ts.type, .listNN("TargetSource"))
        } else { XCTFail("Missing targetSources") }

        // targetMembership(path!, pathMode=FILE_REF): TargetMembership!
        if let tm = field("targetMembership") {
            let pm = tm.args.first { $0.name == "pathMode" }
            XCTAssertEqual(pm?.defaultValue, "FILE_REF")
            XCTAssertEqual(tm.type, .nn("TargetMembership"))
        } else { XCTFail("Missing targetMembership") }
    }

    func testEnumsAndInputsContainExpected() throws {
        let schema = try XQSchemaBuilder.fromGraphQLSwift()
        let enums = Dictionary(uniqueKeysWithValues: schema.enums.map { ($0.name, $0) })
        let inputs = Dictionary(uniqueKeysWithValues: schema.inputs.map { ($0.name, $0) })

        XCTAssertNotNil(enums["TargetType"]) ; XCTAssertNotNil(enums["PathMode"]) ; XCTAssertNotNil(enums["ScriptStage"])
        XCTAssertTrue(Set(enums["PathMode"]!.cases).isSuperset(of: ["FILE_REF", "ABSOLUTE", "NORMALIZED"]))

        XCTAssertNotNil(inputs["StringMatch"]) ; XCTAssertNotNil(inputs["TargetFilter"]) ; XCTAssertNotNil(inputs["SourceFilter"]) ; XCTAssertNotNil(inputs["ResourceFilter"]) ; XCTAssertNotNil(inputs["BuildScriptFilter"]) 

        if let tf = inputs["TargetFilter"] {
            let keys = Set(tf.fields.map { $0.name })
            XCTAssertEqual(keys, ["name", "type"])
        }
    }
}
