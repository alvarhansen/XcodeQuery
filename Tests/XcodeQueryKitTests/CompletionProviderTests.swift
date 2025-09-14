import XCTest
@testable import XcodeQueryCLI

final class CompletionProviderTests: XCTestCase {
    func testFilterRootKeysForTargets() {
        let cp = CompletionProvider()
        let lines = ["targets(filter: { "]
        let col = lines[0].count
        let s = cp.suggest(lines: lines, row: 0, col: col)
        XCTAssertNotNil(s)
        let items = Set(s!.items)
        XCTAssertTrue(items.isSuperset(of: ["name", "type"]))
    }

    func testStringMatchKeysInsideName() {
        let cp = CompletionProvider()
        let lines = ["targets(filter: { name: {"]
        let col = lines[0].count
        let s = cp.suggest(lines: lines, row: 0, col: col)
        XCTAssertNotNil(s)
        let items = Set(s!.items)
        XCTAssertTrue(items.isSuperset(of: ["eq", "regex", "prefix", "suffix", "contains"]))
    }

    func testEnumValuesForTargetType() {
        let cp = CompletionProvider()
        let lines = ["targets(filter: { type: "]
        let col = lines[0].count
        let s = cp.suggest(lines: lines, row: 0, col: col)
        XCTAssertNotNil(s)
        let items = Set(s!.items)
        XCTAssertTrue(items.contains("FRAMEWORK"))
        XCTAssertTrue(items.contains("APP"))
    }

    func testBuildScriptFilterKeysAndEnum() {
        let cp = CompletionProvider()
        let root = ["targetBuildScripts(filter: { "]
        let s1 = cp.suggest(lines: root, row: 0, col: root[0].count)
        XCTAssertNotNil(s1)
        let keys = Set(s1!.items)
        XCTAssertTrue(keys.isSuperset(of: ["stage", "name", "target"]))

        let stage = ["targetBuildScripts(filter: { stage: "]
        let s2 = cp.suggest(lines: stage, row: 0, col: stage[0].count)
        XCTAssertNotNil(s2)
        let enums = Set(s2!.items)
        XCTAssertTrue(enums.isSuperset(of: ["PRE", "POST"]))
    }

    func testSourceFilterKeysAndStringMatch() {
        let cp = CompletionProvider()
        let root = ["targetSources(filter: { "]
        let s1 = cp.suggest(lines: root, row: 0, col: root[0].count)
        XCTAssertNotNil(s1)
        let keys = Set(s1!.items)
        XCTAssertTrue(keys.isSuperset(of: ["path", "target"]))

        let nestedPath = ["targetSources(filter: { path: {"]
        let s2 = cp.suggest(lines: nestedPath, row: 0, col: nestedPath[0].count)
        XCTAssertNotNil(s2)
        let matchKeys = Set(s2!.items)
        XCTAssertTrue(matchKeys.isSuperset(of: ["eq", "regex", "prefix", "suffix", "contains"]))
    }

    func testResourceFilterKeysAndStringMatch() {
        let cp = CompletionProvider()
        let root = ["targetResources(filter: { "]
        let s1 = cp.suggest(lines: root, row: 0, col: root[0].count)
        XCTAssertNotNil(s1)
        let keys = Set(s1!.items)
        XCTAssertTrue(keys.isSuperset(of: ["path", "target"]))

        let nestedTarget = ["targetResources(filter: { target: {"]
        let s2 = cp.suggest(lines: nestedTarget, row: 0, col: nestedTarget[0].count)
        XCTAssertNotNil(s2)
        let matchKeys = Set(s2!.items)
        XCTAssertTrue(matchKeys.isSuperset(of: ["eq", "regex", "prefix", "suffix", "contains"]))
    }

    func testTargetFilterAllCallSites() {
        let cp = CompletionProvider()
        // Top-level dependencies
        let dep = ["dependencies(name: \"App\", filter: { "]
        let s1 = cp.suggest(lines: dep, row: 0, col: dep[0].count)
        XCTAssertNotNil(s1)
        XCTAssertTrue(Set(s1!.items).isSuperset(of: ["name", "type"]))

        // Top-level dependents
        let dnt = ["dependents(name: \"Lib\", filter: { "]
        let s2 = cp.suggest(lines: dnt, row: 0, col: dnt[0].count)
        XCTAssertNotNil(s2)
        XCTAssertTrue(Set(s2!.items).isSuperset(of: ["name", "type"]))

        // targetDependencies (flat view)
        let td = ["targetDependencies(filter: { "]
        let s3 = cp.suggest(lines: td, row: 0, col: td[0].count)
        XCTAssertNotNil(s3)
        XCTAssertTrue(Set(s3!.items).isSuperset(of: ["name", "type"]))

        // nested in Target field selection
        let nested = ["targets { dependencies(filter: { "]
        let s4 = cp.suggest(lines: nested, row: 0, col: nested[0].count)
        XCTAssertNotNil(s4)
        XCTAssertTrue(Set(s4!.items).isSuperset(of: ["name", "type"]))

        // StringMatch inside name
        let match = ["targetDependencies(filter: { name: {"]
        let s5 = cp.suggest(lines: match, row: 0, col: match[0].count)
        XCTAssertNotNil(s5)
        XCTAssertTrue(Set(s5!.items).isSuperset(of: ["eq", "regex", "prefix", "suffix", "contains"]))
    }

    func testSelectionAfterArgumentsProvidesTargetFields() {
        let cp = CompletionProvider()
        let lines = ["targets(filter: { type: APP }) { "]
        let s = cp.suggest(lines: lines, row: 0, col: lines[0].count)
        XCTAssertNotNil(s)
        let items = Set(s!.items)
        XCTAssertTrue(items.isSuperset(of: ["name", "type", "dependencies", "sources", "resources", "buildScripts"]))
        // Should not propose top-level fields here
        XCTAssertFalse(items.contains("targets"))
    }

    func testInsertionBehaviorAddsBracesWhereAppropriate() {
        let cp = CompletionProvider()
        // Selection field 'dependencies' needs selection braces
        let sel = ["targets { dep"]
        let ins1 = cp.insertionBehavior(lines: sel, row: 0, col: sel[0].count, selected: "dependencies")
        XCTAssertTrue(ins1.addSelectionBraces)

        // Filter key 'name' needs input object braces
        let fil = ["targets(filter: { na"]
        let ins2 = cp.insertionBehavior(lines: fil, row: 0, col: fil[0].count, selected: "name")
        XCTAssertTrue(ins2.addInputObjectBraces)

        // Arg 'type' is enum, no braces
        let arg = ["targets( ty"]
        let ins3 = cp.insertionBehavior(lines: arg, row: 0, col: arg[0].count, selected: "type")
        XCTAssertFalse(ins3.addInputObjectBraces)
        XCTAssertFalse(ins3.addSelectionBraces)
    }

    func testRootInsertionAddsSelectionBracesForTargets() {
        let cp = CompletionProvider()
        let lines = ["tar"]
        let ins = cp.insertionBehavior(lines: lines, row: 0, col: lines[0].count, selected: "targets")
        XCTAssertTrue(ins.addSelectionBraces)
        XCTAssertFalse(ins.addInputObjectBraces)
    }

    func testBuildScriptFilterStringMatchNested() {
        let cp = CompletionProvider()
        let nameNested = ["targetBuildScripts(filter: { name: {"]
        let s1 = cp.suggest(lines: nameNested, row: 0, col: nameNested[0].count)
        XCTAssertNotNil(s1)
        XCTAssertTrue(Set(s1!.items).isSuperset(of: ["eq", "regex", "prefix", "suffix", "contains"]))

        let targetNested = ["targetBuildScripts(filter: { target: {"]
        let s2 = cp.suggest(lines: targetNested, row: 0, col: targetNested[0].count)
        XCTAssertNotNil(s2)
        XCTAssertTrue(Set(s2!.items).isSuperset(of: ["eq", "regex", "prefix", "suffix", "contains"]))
    }
}
