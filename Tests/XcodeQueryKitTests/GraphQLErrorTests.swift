import XCTest
@testable import XcodeQueryKit

final class GraphQLErrorTests: XCTestCase {
    func testTopLevelBracesUnsupported() throws {
        let fixture = try GraphQLBaselineFixture()
        XCTAssertThrowsError(try fixture.evaluateToCanonicalJSON(query: "{ targets { name } }")) { error in
            if case let XcodeProjectQuery.Error.invalidQuery(msg) = error {
                XCTAssertEqual(msg, "Top-level braces are not supported. Write selection only, e.g., targets { name type }")
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testUnknownTopLevelField() throws {
        let fixture = try GraphQLBaselineFixture()
        XCTAssertThrowsError(try fixture.evaluateToCanonicalJSON(query: "foobar { name }")) { error in
            let s = String(describing: error)
            XCTAssertTrue(s.contains("Cannot query field") && s.contains("foobar"), s)
        }
    }

    func testTargetsRequiresSelectionSet() throws {
        let fixture = try GraphQLBaselineFixture()
        XCTAssertThrowsError(try fixture.evaluateToCanonicalJSON(query: "targets")) { error in
            let s = String(describing: error)
            XCTAssertTrue(s.contains("selection of subfields"), s)
        }
    }

    func testTargetRequiresSelectionSet() throws {
        let fixture = try GraphQLBaselineFixture()
        XCTAssertThrowsError(try fixture.evaluateToCanonicalJSON(query: "target(name: \"App\")")) { error in
            let s = String(describing: error)
            XCTAssertTrue(s.contains("selection of subfields"), s)
        }
    }

    func testDependenciesMissingNameArgument() throws {
        let fixture = try GraphQLBaselineFixture()
        // Selection set provided, but missing required name argument
        XCTAssertThrowsError(try fixture.evaluateToCanonicalJSON(query: "dependencies { name }")) { error in
            let s = String(describing: error)
            XCTAssertTrue(s.contains("argument \"name\"") || s.contains("argument 'name'"), s)
        }
    }

    func testUnknownFieldOnTarget() throws {
        let fixture = try GraphQLBaselineFixture()
        XCTAssertThrowsError(try fixture.evaluateToCanonicalJSON(query: "targets { nope }")) { error in
            let s = String(describing: error)
            XCTAssertTrue(s.contains("Cannot query field") && s.contains("nope"), s)
        }
    }

    func testUnknownLeafField() throws {
        let fixture = try GraphQLBaselineFixture()
        // targetMembership returns a leaf object; asking for an unknown field should error
        XCTAssertThrowsError(try fixture.evaluateToCanonicalJSON(query: "targetMembership(path: \"Shared/Shared.swift\") { mystery }")) { error in
            let s = String(describing: error)
            XCTAssertTrue(s.contains("Cannot query field") && s.contains("mystery"), s)
        }
    }

    func testUnknownTargetLookup() throws {
        let fixture = try GraphQLBaselineFixture()
        XCTAssertThrowsError(try fixture.evaluateToCanonicalJSON(query: "target(name: \"Nope\") { name }")) { error in
            let s = String(describing: error)
            XCTAssertTrue(s.contains("Unknown target: Nope"), s)
        }
    }

    func testParseError_UnterminatedString() throws {
        let fixture = try GraphQLBaselineFixture()
        // Missing closing quote in string literal
        XCTAssertThrowsError(try fixture.evaluateToCanonicalJSON(query: "target(name: \"App) { name }")) { error in
            let s = String(describing: error)
            XCTAssertTrue(s.lowercased().contains("unterminated") || s.lowercased().contains("syntax"), s)
        }
    }

    func testParseError_ExpectedIdentifier() throws {
        let fixture = try GraphQLBaselineFixture()
        // Invalid argument list — starts with a number instead of key: value
        XCTAssertThrowsError(try fixture.evaluateToCanonicalJSON(query: "targets(123) { name }")) { error in
            let s = String(describing: error)
            XCTAssertTrue(s.contains("Expected") || s.contains("expected"), s)
        }
    }
}
