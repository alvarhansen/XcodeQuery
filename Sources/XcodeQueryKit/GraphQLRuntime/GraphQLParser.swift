import Foundation

struct GQLSelection {
    let name: String
    let arguments: [String: Map]
    let selectionSet: [GQLSelection]?
}

struct GQLParseError: Error {
    let message: String
    let position: Int

    var formatted: String { "Parse error: \(message) @\(position)" }
}

struct GQLParser {
    private enum TokenKind {
        case name(String)
        case string(String)
        case int(Int)
        case float(Double)
        case lbrace
        case rbrace
        case lparen
        case rparen
        case lbracket
        case rbracket
        case colon
        case comma
        case eof
    }

    private struct Token {
        let kind: TokenKind
        let position: Int
    }

    private let chars: [Character]
    private var index: Int = 0
    private var lookahead: Token?

    init(_ source: String) {
        self.chars = Array(source)
    }

    mutating func parseDocument() throws -> [GQLSelection] {
        let tok = try peek()
        switch tok.kind {
        case .lbrace:
            _ = try advance()
            let selections = try parseSelectionSet(until: .rbrace)
            try expect(.rbrace)
            try expect(.eof)
            return selections
        case .eof:
            throw error("Unexpected end of input", position: tok.position)
        default:
            let selections = try parseSelectionSet(until: .eof)
            try expect(.eof)
            return selections
        }
    }

    private mutating func parseSelectionSet(until end: TokenKind) throws -> [GQLSelection] {
        var selections: [GQLSelection] = []
        while true {
            let tok = try peek()
            if matches(tok, end) { break }
            if case .comma = tok.kind { _ = try advance(); continue }
            if case .eof = tok.kind { break }
            selections.append(try parseSelection())
            let next = try peek()
            if case .comma = next.kind { _ = try advance() }
        }
        if selections.isEmpty {
            throw error("Expected identifier", position: (try peek()).position)
        }
        return selections
    }

    private mutating func parseSelection() throws -> GQLSelection {
        let nameTok = try expectName()
        var args: [String: Map] = [:]
        if case .lparen = try peek().kind {
            args = try parseArguments()
        }
        var selectionSet: [GQLSelection]? = nil
        if case .lbrace = try peek().kind {
            _ = try advance()
            selectionSet = try parseSelectionSet(until: .rbrace)
            try expect(.rbrace)
        }
        return GQLSelection(name: nameTok, arguments: args, selectionSet: selectionSet)
    }

    private mutating func parseArguments() throws -> [String: Map] {
        try expect(.lparen)
        var args: [String: Map] = [:]
        while true {
            let tok = try peek()
            if case .rparen = tok.kind { _ = try advance(); break }
            if case .comma = tok.kind { _ = try advance(); continue }
            let name = try expectName()
            try expect(.colon)
            let value = try parseValue()
            args[name] = value
            let next = try peek()
            if case .comma = next.kind { _ = try advance() }
        }
        return args
    }

    private mutating func parseValue() throws -> Map {
        let tok = try advance()
        switch tok.kind {
        case .string(let s):
            return .string(s)
        case .int(let i):
            return .number(Double(i))
        case .float(let d):
            return .number(d)
        case .name(let s):
            switch s {
            case "true": return .bool(true)
            case "false": return .bool(false)
            case "null": return .null
            default:
                return .string(s)
            }
        case .lbracket:
            var items: [Map] = []
            while true {
                let next = try peek()
                if case .rbracket = next.kind { _ = try advance(); break }
                if case .comma = next.kind { _ = try advance(); continue }
                items.append(try parseValue())
                let after = try peek()
                if case .comma = after.kind { _ = try advance() }
            }
            return .array(items)
        case .lbrace:
            var dict: [String: Map] = [:]
            while true {
                let next = try peek()
                if case .rbrace = next.kind { _ = try advance(); break }
                if case .comma = next.kind { _ = try advance(); continue }
                let key = try expectName()
                try expect(.colon)
                dict[key] = try parseValue()
                let after = try peek()
                if case .comma = after.kind { _ = try advance() }
            }
            return .dictionary(dict)
        default:
            throw error("Expected value", position: tok.position)
        }
    }

    private mutating func expectName() throws -> String {
        let tok = try advance()
        if case .name(let s) = tok.kind { return s }
        throw error("Expected identifier", position: tok.position)
    }

    private mutating func expect(_ kind: TokenKind) throws {
        let tok = try advance()
        if !matches(tok, kind) {
            let expected = tokenDescription(kind)
            throw error("Expected \(expected)", position: tok.position)
        }
    }

    private func matches(_ tok: Token, _ kind: TokenKind) -> Bool {
        switch (tok.kind, kind) {
        case (.lbrace, .lbrace), (.rbrace, .rbrace), (.lparen, .lparen), (.rparen, .rparen),
             (.lbracket, .lbracket), (.rbracket, .rbracket), (.colon, .colon), (.comma, .comma), (.eof, .eof):
            return true
        default:
            return false
        }
    }

    private func tokenDescription(_ kind: TokenKind) -> String {
        switch kind {
        case .lbrace: return "'{'"
        case .rbrace: return "'}'"
        case .lparen: return "'('"
        case .rparen: return "')'"
        case .lbracket: return "'['"
        case .rbracket: return "']'"
        case .colon: return "':'"
        case .comma: return "','"
        case .eof: return "end of input"
        case .name: return "identifier"
        case .string: return "string"
        case .int: return "int"
        case .float: return "float"
        }
    }

    private mutating func peek() throws -> Token {
        if let lookahead { return lookahead }
        let tok = try nextToken()
        self.lookahead = tok
        return tok
    }

    @discardableResult
    private mutating func advance() throws -> Token {
        if let lookahead {
            self.lookahead = nil
            return lookahead
        }
        return try nextToken()
    }

    private mutating func nextToken() throws -> Token {
        skipWhitespaceAndComments()
        if index >= chars.count {
            return Token(kind: .eof, position: max(1, chars.count + 1))
        }
        let pos = index + 1
        let ch = chars[index]
        switch ch {
        case "{": index += 1; return Token(kind: .lbrace, position: pos)
        case "}": index += 1; return Token(kind: .rbrace, position: pos)
        case "(": index += 1; return Token(kind: .lparen, position: pos)
        case ")": index += 1; return Token(kind: .rparen, position: pos)
        case "[": index += 1; return Token(kind: .lbracket, position: pos)
        case "]": index += 1; return Token(kind: .rbracket, position: pos)
        case ":": index += 1; return Token(kind: .colon, position: pos)
        case ",": index += 1; return Token(kind: .comma, position: pos)
        case "\"":
            return try readStringToken()
        default:
            if isNameStart(ch) {
                return readNameToken()
            }
            if ch == "-" || ch.isNumber {
                return readNumberToken()
            }
            throw error("Unexpected character \"\(ch)\"", position: pos)
        }
    }

    private mutating func readStringToken() throws -> Token {
        let start = index + 1
        index += 1 // consume opening quote
        var buffer: [Character] = []
        while index < chars.count {
            let ch = chars[index]
            index += 1
            if ch == "\"" {
                let s = String(buffer)
                return Token(kind: .string(s), position: start)
            }
            if ch == "\\" {
                if index >= chars.count { break }
                let esc = chars[index]
                index += 1
                switch esc {
                case "\"": buffer.append("\"")
                case "\\": buffer.append("\\")
                case "n": buffer.append("\n")
                case "t": buffer.append("\t")
                case "r": buffer.append("\r")
                default: buffer.append(esc)
                }
            } else {
                buffer.append(ch)
            }
        }
        throw error("Unterminated string literal", position: start)
    }

    private mutating func readNameToken() -> Token {
        let start = index + 1
        var end = index + 1
        while end < chars.count && isNameContinue(chars[end]) { end += 1 }
        let s = String(chars[index..<end])
        index = end
        return Token(kind: .name(s), position: start)
    }

    private mutating func readNumberToken() -> Token {
        let start = index + 1
        var end = index
        if chars[end] == "-" { end += 1 }
        while end < chars.count && chars[end].isNumber { end += 1 }
        var isFloat = false
        if end < chars.count && chars[end] == "." {
            isFloat = true
            end += 1
            while end < chars.count && chars[end].isNumber { end += 1 }
        }
        let s = String(chars[index..<end])
        index = end
        if isFloat {
            return Token(kind: .float(Double(s) ?? 0), position: start)
        }
        return Token(kind: .int(Int(s) ?? 0), position: start)
    }

    private mutating func skipWhitespaceAndComments() {
        while index < chars.count {
            let ch = chars[index]
            if ch == "#" {
                while index < chars.count && chars[index] != "\n" { index += 1 }
                continue
            }
            if ch.isWhitespace {
                index += 1
                continue
            }
            break
        }
    }

    private func isNameStart(_ ch: Character) -> Bool {
        return ch == "_" || ch.isLetter
    }

    private func isNameContinue(_ ch: Character) -> Bool {
        return ch == "_" || ch.isLetter || ch.isNumber
    }

    private func error(_ message: String, position: Int) -> GQLParseError {
        GQLParseError(message: message, position: position)
    }
}
