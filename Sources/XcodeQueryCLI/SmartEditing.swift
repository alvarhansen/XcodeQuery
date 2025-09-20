import Foundation

// Internal helpers for interactive smart editing (indent, balance, caret).
// Exposed as internal for unit tests in XcodeQueryKitTests.
struct SmartEditing {
    static let indentWidth: Int = 2

    // Scan text and compute balance for curlies and parens, ignoring string literals.
    // Returns positive depths for unmatched openings (negative if more closings).
    static func computeBalance(_ text: String) -> (balanced: Bool, depthCurlies: Int, depthParens: Int) {
        var depthCurlies = 0
        var depthParens = 0
        var inString = false
        var escape = false
        for ch in text {
            if inString {
                if escape { escape = false; continue }
                if ch == "\\" { escape = true; continue }
                if ch == "\"" { inString = false }
                continue
            } else {
                if ch == "\"" { inString = true; escape = false; continue }
                switch ch {
                case "{": depthCurlies += 1
                case "}": depthCurlies -= 1
                case "(": depthParens += 1
                case ")": depthParens -= 1
                default: break
                }
            }
        }
        let balanced = depthCurlies == 0 && depthParens == 0 && !inString
        return (balanced, depthCurlies, depthParens)
    }

    // Compute spaces for a newly inserted line at (beforeRow, col), given buffer lines.
    // Applies classic outdent if the right slice starts with a closing brace/paren.
    static func computeIndentForNewLine(lines: [String], beforeRow: Int, col: Int, indentWidth: Int = SmartEditing.indentWidth) -> Int {
        // Walk all content before the insertion point
        var depthCurlies = 0
        var depthParens = 0
        var inString = false
        var escape = false
        let lastRow = max(0, min(beforeRow, lines.count == 0 ? 0 : lines.count - 1))
        for r in 0...lastRow {
            let line = lines[r]
            let upTo = (r == beforeRow) ? min(col, line.count) : line.count
            var idx = line.startIndex
            for _ in 0..<upTo {
                let ch = line[idx]
                idx = line.index(after: idx)
                if inString {
                    if escape { escape = false; continue }
                    if ch == "\\" { escape = true; continue }
                    if ch == "\"" { inString = false }
                    continue
                } else {
                    if ch == "\"" { inString = true; escape = false; continue }
                    switch ch {
                    case "{": depthCurlies += 1
                    case "}": depthCurlies -= 1
                    case "(": depthParens += 1
                    case ")": depthParens -= 1
                    default: break
                    }
                }
            }
        }
        // Look ahead for outdent: only if the right slice of the current line starts with a closer
        var outdent = 0
        if beforeRow < lines.count {
            let line = lines[beforeRow]
            let right = String(line.dropFirst(min(col, line.count)))
            if let firstNonSpace = right.first(where: { !$0.isWhitespace }) {
                if firstNonSpace == "}" || firstNonSpace == ")" { outdent = 1 }
            }
        }
        let depth = max(0, depthCurlies + depthParens - outdent)
        return max(0, depth) * indentWidth
    }

    // Return the new column after a smart backspace in leading spaces.
    // If within leading spaces, go to previous indent stop; otherwise col - 1 (down to 0).
    static func smartBackspaceColumn(for line: String, col: Int, indentWidth: Int = SmartEditing.indentWidth) -> Int {
        let c = max(0, min(col, line.count))
        if c == 0 { return 0 }
        // Check if within leading spaces
        let prefix = String(line.prefix(c))
        if prefix.allSatisfy({ $0 == " " }) {
            let prevStop = ((c - 1) / indentWidth) * indentWidth
            return max(0, prevStop)
        }
        return c - 1
    }

    // Map a character position in the full buffer to (row, col)
    static func mapPosition(_ text: String, position: Int) -> (row: Int, col: Int) {
        let chars = Array(text)
        let p = max(0, min(position, chars.count))
        var row = 0
        var col = 0
        for i in 0..<p {
            if chars[i] == "\n" { row += 1; col = 0 } else { col += 1 }
        }
        return (row, col)
    }

    // Build a caret line with spaces then a caret at the given column.
    static func caretLine(for line: String, col: Int) -> String {
        let c = max(0, min(col, line.count))
        return String(repeating: " ", count: c) + "^"
    }

    // Expand a new block on Enter when the caret is positioned immediately after an
    // opening '{' or '(', allowing only whitespace between the opener and caret.
    // Returns whether expansion was applied, and the updated buffer with new cursor.
    static func expandBlockOnEnter(lines: [String], row: Int, col: Int, indentWidth: Int = SmartEditing.indentWidth) -> (applied: Bool, newLines: [String], cursorRow: Int, cursorCol: Int) {
        guard row >= 0 && row < lines.count else { return (false, lines, row, col) }
        let line = lines[row]
        let c = max(0, min(col, line.count))
        let splitIdx = line.index(line.startIndex, offsetBy: c)
        let left = String(line[..<splitIdx])
        let right = String(line[splitIdx...])

        // Find last non-whitespace on the left
        if let lastNonWS = left.lastIndex(where: { !$0.isWhitespace }) {
            let ch = left[lastNonWS]
            guard ch == "{" || ch == "(" else { return (false, lines, row, col) }
            // Ensure only whitespace between the opener and caret
            let afterOpen = left.index(after: lastNonWS)
            let onlyWS = left[afterOpen...].allSatisfy { $0.isWhitespace }
            guard onlyWS else { return (false, lines, row, col) }

            let closing: Character = (ch == "{") ? "}" : ")"
            // Allow moving an immediate closer on the same line; other closers are handled by indent-aware check below.
            var indentInner = computeIndentForNewLine(lines: lines, beforeRow: row, col: c, indentWidth: indentWidth)
            if indentInner == 0 { indentInner = indentWidth }
            let indentClose = max(0, indentInner - indentWidth)

            // If there's already a closer for this opener ahead at the expected indent, don't expand
            if let (foundIndent, _) = findNextCloserAhead(lines: lines, fromRow: row + 1, closer: closing), foundIndent == indentClose {
                return (false, lines, row, col)
            }

            // Prepare trimmed right: drop leading spaces and a single closing token if present
            var trimmedRight = right
            while let first = trimmedRight.first, first == " " { trimmedRight.removeFirst() }
            if let first = trimmedRight.first, first == closing { trimmedRight.removeFirst() }

            var out = lines
            // Replace current line with left trimmed (drop trailing spaces)
            let leftTrimmed = left.replacingOccurrences(of: " +$", with: "", options: .regularExpression)
            out[row] = leftTrimmed
            let innerLine = String(repeating: " ", count: indentInner)
            let closeLine = String(repeating: " ", count: indentClose) + String(closing) + String(trimmedRight)
            out.insert(innerLine, at: row + 1)
            out.insert(closeLine, at: row + 2)
            return (true, out, row + 1, indentInner)
        }
        return (false, lines, row, col)
    }

    // (removed hasMatchingCloserAhead; using indent-aware search instead)

    // Find the first closer token on a subsequent line and return its leading-space indent and line index.
    private static func findNextCloserAhead(lines: [String], fromRow: Int, closer: Character) -> (Int, Int)? {
        guard fromRow < lines.count else { return nil }
        for r in fromRow..<lines.count {
            let s = lines[r]
            var spaces = 0
            var i = s.startIndex
            while i < s.endIndex, s[i] == " " { spaces += 1; i = s.index(after: i) }
            if i < s.endIndex, s[i] == closer {
                return (spaces, r)
            }
        }
        return nil
    }
}
