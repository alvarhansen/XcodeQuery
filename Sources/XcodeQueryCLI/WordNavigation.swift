import Foundation

enum WordNavigation {
    private static func isWordChar(_ c: Character) -> Bool {
        if c == "_" { return true }
        return c.isLetter || c.isNumber
    }

    static func previousWordIndex(in line: String, fromCol: Int) -> Int {
        if line.isEmpty { return 0 }
        let chars = Array(line)
        var i = max(0, min(fromCol, chars.count))
        // Step back one if at a boundary
        if i > 0 { i -= 1 }
        // Skip whitespace and non-word
        while i > 0 && !isWordChar(chars[i]) { i -= 1 }
        // Move to start of word
        while i > 0 && isWordChar(chars[i-1]) { i -= 1 }
        return i
    }

    static func nextWordIndex(in line: String, fromCol: Int) -> Int {
        if line.isEmpty { return 0 }
        let chars = Array(line)
        var i = max(0, min(fromCol, chars.count))
        // Skip non-word
        while i < chars.count && !isWordChar(chars[i]) { i += 1 }
        // Skip word
        while i < chars.count && isWordChar(chars[i]) { i += 1 }
        return i
    }
}

