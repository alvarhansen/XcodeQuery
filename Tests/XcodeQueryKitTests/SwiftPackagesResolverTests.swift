import XCTest
@testable import XcodeQueryKit

final class SwiftPackagesResolverTests: XCTestCase {
    func testSwiftPackagesRootAndConsumers() throws {
        let fx = try SwiftPackagesFixture()
        let q = """
        swiftPackages { name identity url requirement { kind value } products { name type } consumers { target product } }
        """
        let out = try fx.evaluateToCanonicalJSON(query: q)
        // Basic presence checks
        XCTAssertTrue(out.contains("\"name\" : \"A\""))
        XCTAssertTrue(out.contains("\"identity\" : \"a\""))
        XCTAssertTrue(out.contains("\"name\" : \"B\""))
        XCTAssertTrue(out.contains("\"identity\" : \"b\""))
        XCTAssertTrue(out.contains("\"kind\" : \"EXACT\""))
        XCTAssertTrue(out.contains("\"kind\" : \"UP_TO_NEXT_MAJOR\""))
        // Products and consumers present
        XCTAssertTrue(out.contains("\"name\" : \"ACore\""))
        XCTAssertTrue(out.contains("\"name\" : \"BUI\""))
        XCTAssertTrue(out.contains("\"target\" : \"App\""))
        XCTAssertTrue(out.contains("\"product\" : \"ACore\""))
        XCTAssertTrue(out.contains("\"product\" : \"BTool\""))
    }

    func testTargetPackageProductsAndFilters() throws {
        let fx = try SwiftPackagesFixture()
        // Target field
        let t = try fx.evaluateToCanonicalJSON(query: "target(name: \"App\") { packageProducts { packageName productName } }")
        XCTAssertTrue(t.contains("\"packageName\" : \"A\""))
        XCTAssertTrue(t.contains("\"productName\" : \"ACore\""))
        XCTAssertTrue(t.contains("\"packageName\" : \"B\""))
        XCTAssertTrue(t.contains("\"productName\" : \"BUI\""))

        // Flat view
        let f1 = try fx.evaluateToCanonicalJSON(query: "targetPackageProducts { target packageName productName }")
        XCTAssertTrue(f1.contains("\"target\" : \"Tool\""))
        XCTAssertTrue(f1.contains("\"productName\" : \"BTool\""))

        let f2 = try fx.evaluateToCanonicalJSON(query: "targetPackageProducts(filter: { target: { eq: \"Tool\" } }) { target packageName productName }")
        // Only Tool rows present
        XCTAssertTrue(f2.contains("\"target\" : \"Tool\""))
        XCTAssertFalse(f2.contains("\"target\" : \"App\""))
    }
}

