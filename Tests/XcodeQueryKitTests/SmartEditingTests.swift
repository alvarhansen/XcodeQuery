import XCTest
@testable import XcodeQueryCLI

final class SmartEditingTests: XCTestCase {
    func testBalanceComputation() {
        // Simple balanced
        XCTAssertEqual(SmartEditing.computeBalance("targets { name }" ).balanced, true)
        // Nested parens
        let b1 = SmartEditing.computeBalance("field(arg: foo(bar: 1)) { name }")
        XCTAssertTrue(b1.balanced)
        // Unbalanced curlies
        let b2 = SmartEditing.computeBalance("a { b { c }")
        XCTAssertFalse(b2.balanced)
        XCTAssertEqual(b2.depthCurlies, 1)
        // Ignore braces in strings and escapes
        let b3 = SmartEditing.computeBalance("name: \"{ not a brace }\"")
        XCTAssertTrue(b3.balanced)
        let b4 = SmartEditing.computeBalance("name: \"\\\"\" {\"") // string with escaped quote then more
        XCTAssertFalse(b4.balanced) // unmatched '{'
        XCTAssertEqual(b4.depthCurlies, 1)
    }

    func testIndentComputation() {
        let lines = [
            "targets {",
            "  name"
        ]
        // Press Enter at end of second line: expect indent level 2 * depth 1 (inside targets set)
        let indent1 = SmartEditing.computeIndentForNewLine(lines: lines, beforeRow: 1, col: lines[1].count)
        XCTAssertEqual(indent1, 2)

        // New line after opening brace should indent inside selection
        let lines2 = ["targets {", "  }"]
        let indent2 = SmartEditing.computeIndentForNewLine(lines: lines2, beforeRow: 0, col: lines2[0].count)
        XCTAssertEqual(indent2, 2)
    }

    func testSmartBackspace() {
        let line = "      name" // 6 spaces
        XCTAssertEqual(SmartEditing.smartBackspaceColumn(for: line, col: 6), 4)
        XCTAssertEqual(SmartEditing.smartBackspaceColumn(for: line, col: 5), 4)
        XCTAssertEqual(SmartEditing.smartBackspaceColumn(for: line, col: 1), 0)
        // Non-leading region: delete single char
        XCTAssertEqual(SmartEditing.smartBackspaceColumn(for: line, col: 7), 6)
    }

    func testPositionMapping() {
        let text = "ab\ncd\nef"
        // positions: 0 a,1 b,2 \n,3 c,4 d,5 \n,6 e,7 f
        XCTAssertEqual(SmartEditing.mapPosition(text, position: 0).row, 0)
        XCTAssertEqual(SmartEditing.mapPosition(text, position: 0).col, 0)
        XCTAssertEqual(SmartEditing.mapPosition(text, position: 3).row, 1)
        XCTAssertEqual(SmartEditing.mapPosition(text, position: 3).col, 0)
        XCTAssertEqual(SmartEditing.mapPosition(text, position: 7).row, 2)
        XCTAssertEqual(SmartEditing.mapPosition(text, position: 7).col, 1)
    }

    func testCaretRenderingAlignment() {
        let line = "  name"
        let caret = SmartEditing.caretLine(for: line, col: 2)
        XCTAssertEqual(caret, "  ^")
        let caret2 = SmartEditing.caretLine(for: line, col: 4)
        XCTAssertEqual(caret2, "    ^")
    }

    func testSmartEnterBlockExpansion() {
        // Case 1: caret after space following '{' with no existing closer
        do {
            let line = "targets { "
            let exp = SmartEditing.expandBlockOnEnter(lines: [line], row: 0, col: line.count)
            XCTAssertTrue(exp.applied)
            XCTAssertEqual(exp.newLines.count, 3)
            XCTAssertEqual(exp.newLines[0], "targets {") // trailing space trimmed
            XCTAssertEqual(exp.newLines[1], "  ")       // inner indent
            XCTAssertEqual(exp.newLines[2], "}")        // closing on next line
            XCTAssertEqual(exp.cursorRow, 1)
            XCTAssertEqual(exp.cursorCol, 2)
        }
        // Case 2: caret before an existing closing brace
        do {
            let line = "targets { }"
            // caret just before the '}'
            let caretCol = line.firstIndex(of: "}").map { line.distance(from: line.startIndex, to: $0) }! - 0
            let exp = SmartEditing.expandBlockOnEnter(lines: [line], row: 0, col: caretCol)
            XCTAssertTrue(exp.applied)
            XCTAssertEqual(exp.newLines[0], "targets {")
            XCTAssertEqual(exp.newLines[1], "  ")
            XCTAssertEqual(exp.newLines[2], "}")
            XCTAssertEqual(exp.cursorRow, 1)
            XCTAssertEqual(exp.cursorCol, 2)
        }
        // Case 3: nested braces -> indent 4
        do {
            let line = "targets { dependencies { "
            let exp = SmartEditing.expandBlockOnEnter(lines: [line], row: 0, col: line.count)
            XCTAssertTrue(exp.applied)
            XCTAssertEqual(exp.newLines[0], "targets { dependencies {")
            XCTAssertEqual(exp.newLines[1], "    ") // 4 spaces
            XCTAssertEqual(exp.newLines[2], "  }")  // close one level
            XCTAssertEqual(exp.cursorRow, 1)
            XCTAssertEqual(exp.cursorCol, 4)
        }
        // Case 4: multi-step nested editing mirrors interactive behavior
        do {
            var lines = ["targets { "]
            // First expansion at top-level
            var exp = SmartEditing.expandBlockOnEnter(lines: lines, row: 0, col: lines[0].count)
            XCTAssertTrue(exp.applied)
            lines = exp.newLines
            // User types nested field opener on the inner blank line
            lines[1] = "  dependencies { "
            exp = SmartEditing.expandBlockOnEnter(lines: lines, row: 1, col: lines[1].count)
            XCTAssertTrue(exp.applied)
            XCTAssertEqual(exp.newLines, [
                "targets {",
                "  dependencies {",
                "    ",
                "  }",
                "}"
            ])
            XCTAssertEqual(exp.cursorRow, 2)
            XCTAssertEqual(exp.cursorCol, 4)
        }
    }

    func testSmartEnterDoesNotDuplicateCloserWhenAlreadyBalanced() {
        // Prepare a buffer where the opener already has a closing brace below
        let lines = [
            "targets {",
            "  dependencies {",
            "    ",
            "  }",
            "}"
        ]
        // Caret is at end of the opener line (row 1)
        let exp = SmartEditing.expandBlockOnEnter(lines: lines, row: 1, col: lines[1].count)
        XCTAssertFalse(exp.applied)
        // Default indent for a newline at that point should be 4 spaces
        let indent = SmartEditing.computeIndentForNewLine(lines: lines, beforeRow: 1, col: lines[1].count)
        XCTAssertEqual(indent, 4)
    }
}
