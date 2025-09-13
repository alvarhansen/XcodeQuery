import Foundation
import XcodeQueryKit

struct CompletionProvider {
    struct Suggestions { let items: [String]; let replaceStartCol: Int; let replaceEndCol: Int }

    private let schema: XQSchema
    private let typesByName: [String: XQObjectType]

    init(schema: XQSchema = XcodeQuerySchema.schema) {
        self.schema = schema
        self.typesByName = Dictionary(uniqueKeysWithValues: schema.types.map { ($0.name, $0) })
    }

    func suggest(lines: [String], row: Int, col: Int) -> Suggestions? {
        let (prefix, startCol, endCol) = currentWord(in: lines[row], col: col)

        // Determine context by scanning tokens up to the cursor
        let ctx = scanContext(lines: lines, row: row, col: col)

        let items: [String]
        switch ctx.mode {
        case .root:
            items = schema.topLevel.map { $0.name }.filter { $0.hasPrefix(prefix) }
        case .selection(let typeName):
            guard let obj = typesByName[typeName] else { items = []; break }
            items = obj.fields.map { $0.name }.filter { $0.hasPrefix(prefix) }
        case .arguments(let typeName, let field, let argNameForValue, let used):
            if let argName = argNameForValue, let arg = field.args.first(where: { $0.name == argName }) {
                // Value suggestions: only for enums
                if case let .named(enumName, _) = arg.type, let en = schema.enums.first(where: { $0.name == enumName }) {
                    items = en.cases.filter { $0.hasPrefix(prefix.uppercased()) }
                } else {
                    items = []
                }
            } else {
                // Argument name suggestions (exclude used)
                items = field.args.map { $0.name }.filter { !used.contains($0) && $0.hasPrefix(prefix) }
            }
        }
        if items.isEmpty { return nil }
        return Suggestions(items: items, replaceStartCol: startCol, replaceEndCol: endCol)
    }

    // MARK: - Context scanning
    private enum Mode { case root, selection(String), arguments(String, XQField, currentArgName: String?, used: Set<String>) }
    private struct Ctx { var mode: Mode }

    private func scanContext(lines: [String], row: Int, col: Int) -> Ctx {
        enum Tok { case ident(String), lbrace, rbrace, lparen, rparen, colon, comma, string }
        func tokenize(_ s: String) -> [Tok] {
            var out: [Tok] = []
            let chars = Array(s)
            var i = 0
            func isIdentStart(_ c: Character) -> Bool { c.isLetter || c == "_" }
            func isIdentCont(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
            while i < chars.count {
                let ch = chars[i]
                if ch == "\"" { // string
                    i += 1
                    while i < chars.count {
                        let c = chars[i]; i += 1
                        if c == "\\" { if i < chars.count { i += 1 } ; continue }
                        if c == "\"" { break }
                    }
                    out.append(.string)
                } else if ch.isWhitespace { i += 1 }
                else if ch == "{" { out.append(.lbrace); i += 1 }
                else if ch == "}" { out.append(.rbrace); i += 1 }
                else if ch == "(" { out.append(.lparen); i += 1 }
                else if ch == ")" { out.append(.rparen); i += 1 }
                else if ch == ":" { out.append(.colon); i += 1 }
                else if ch == "," { out.append(.comma); i += 1 }
                else if isIdentStart(ch) {
                    var j = i + 1
                    while j < chars.count && isIdentCont(chars[j]) { j += 1 }
                    out.append(.ident(String(chars[i..<j])))
                    i = j
                } else {
                    i += 1 // skip
                }
            }
            return out
        }

        let rootType = "Query"
        var typeStack: [String] = [rootType]
        struct ArgFrame { let typeName: String; let field: XQField; var usedArgs: Set<String> }
        var argStack: [ArgFrame] = []
        var lastIdent: String? = nil
        var lastColonArgName: String? = nil

        func findField(typeName: String, name: String) -> XQField? {
            if typeName == rootType { return schema.topLevel.first(where: { $0.name == name }) }
            return typesByName[typeName]?.fields.first(where: { $0.name == name })
        }
        func underlyingObject(_ t: XQSTypeRef) -> String? {
            switch t {
            case .named(let name, _): return typesByName[name] != nil ? name : nil
            case .list(let of, _, _): return underlyingObject(of)
            }
        }

        // Walk all lines up to the target row/col
        for r in 0...row {
            let line = lines[r]
            let slice = r == row ? String(line.prefix(col)) : line
            let toks = tokenize(slice)
            for t in toks {
                switch t {
                case .ident(let s):
                    lastIdent = s
                case .lparen:
                    if let name = lastIdent, let f = findField(typeName: typeStack.last ?? rootType, name: name) {
                        argStack.append(ArgFrame(typeName: typeStack.last ?? rootType, field: f, usedArgs: []))
                        lastColonArgName = nil
                    }
                case .rparen:
                    _ = argStack.popLast(); lastColonArgName = nil
                case .lbrace:
                    if let name = lastIdent, let f = findField(typeName: typeStack.last ?? rootType, name: name), let obj = underlyingObject(f.type) {
                        typeStack.append(obj)
                    }
                case .rbrace:
                    if typeStack.count > 1 { _ = typeStack.popLast() }
                case .colon:
                    if let name = lastIdent, var top = argStack.popLast() {
                        top.usedArgs.insert(name)
                        argStack.append(top)
                        lastColonArgName = name
                    }
                case .comma:
                    lastColonArgName = nil
                case .string:
                    break
                }
            }
        }

        if let top = argStack.last {
            return Ctx(mode: .arguments(top.typeName, top.field, currentArgName: lastColonArgName, used: top.usedArgs))
        }
        if let typeName = typeStack.last, typeName != rootType {
            return Ctx(mode: .selection(typeName))
        }
        return Ctx(mode: .root)
    }

    // Find current identifier under cursor and its replace range
    private func currentWord(in line: String, col: Int) -> (String, Int, Int) {
        if line.isEmpty { return ("", col, col) }
        let chars = Array(line)
        let n = chars.count
        var left = max(0, min(col, n))
        var right = left
        func isIdent(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        // Extend left
        while left > 0 && isIdent(chars[left - 1]) { left -= 1 }
        // Extend right
        while right < n && isIdent(chars[right]) { right += 1 }
        let prefix = left < right ? String(chars[left..<right]) : ""
        return (prefix, left, right)
    }
}

