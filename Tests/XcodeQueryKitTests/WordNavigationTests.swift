import XCTest
@testable import XcodeQueryCLI

final class WordNavigationTests: XCTestCase {
    func testPreviousWordIndex() {
        let s = " targets  {  name_type }"
        // At end, should jump to start of 'name_type'
        let startName = s.firstIndex(of: "n").map { s.distance(from: s.startIndex, to: $0) }!
        XCTAssertEqual(WordNavigation.previousWordIndex(in: s, fromCol: s.count), startName)
        // In middle of name_type, go to start of name_type
        let col = s.firstIndex(of: "_").map { s.distance(from: s.startIndex, to: $0) }! + 1
        XCTAssertEqual(WordNavigation.previousWordIndex(in: s, fromCol: col), s.firstIndex(of: "n").map { s.distance(from: s.startIndex, to: $0) }!)
    }

    func testNextWordIndex() {
        let s = " targets  {  name_type }"
        // At 0, skip space to 'targets', then skip word -> index after 'targets'
        let idxAfterTargets = " targets".count
        XCTAssertEqual(WordNavigation.nextWordIndex(in: s, fromCol: 0), idxAfterTargets)
        // From start of name_type, move to end of name_type
        let startName = s.firstIndex(of: "n").map { s.distance(from: s.startIndex, to: $0) }!
        let endName = startName + "name_type".count
        XCTAssertEqual(WordNavigation.nextWordIndex(in: s, fromCol: startName), endName)
    }
}
