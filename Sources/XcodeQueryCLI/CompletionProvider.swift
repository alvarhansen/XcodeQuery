import Foundation
import XcodeQueryKit

struct CompletionProvider {
    struct Suggestions { let items: [String]; let replaceStartCol: Int; let replaceEndCol: Int }
    struct Insertion { let addSelectionBraces: Bool; let addInputObjectBraces: Bool }

    private let schema: XQSchema
    private let typesByName: [String: XQObjectType]
    private let inputsByName: [String: XQInputObjectType]

    init(schema: XQSchema? = nil) {
        let resolved = schema ?? (try! XQSchemaBuilder.fromGraphQLSwift())
        self.schema = resolved
        self.typesByName = Dictionary(uniqueKeysWithValues: resolved.types.map { ($0.name, $0) })
        self.inputsByName = Dictionary(uniqueKeysWithValues: resolved.inputs.map { ($0.name, $0) })
    }

    private func underlyingObject(_ t: XQSTypeRef) -> String? {
        switch t {
        case .named(let name, _): return typesByName[name] != nil ? name : nil
        case .list(let of, _, _): return underlyingObject(of)
        }
    }
    private func underlyingInput(_ t: XQSTypeRef) -> XQInputObjectType? {
        switch t {
        case .named(let name, _): return inputsByName[name]
        case .list(let of, _, _): return underlyingInput(of)
        }
    }

    // Decide if accepting a suggestion should append braces and where.
    func insertionBehavior(lines: [String], row: Int, col: Int, selected: String) -> Insertion {
        let ctx = scanContext(lines: lines, row: row, col: col)
        switch ctx.mode {
        case .root:
            if let f = schema.topLevel.first(where: { $0.name == selected }) {
                if underlyingObject(f.type) != nil { return Insertion(addSelectionBraces: true, addInputObjectBraces: false) }
            }
            return Insertion(addSelectionBraces: false, addInputObjectBraces: false)
        case .selection(let typeName):
            if let obj = typesByName[typeName], let f = obj.fields.first(where: { $0.name == selected }) {
                if underlyingObject(f.type) != nil { return Insertion(addSelectionBraces: true, addInputObjectBraces: false) }
            }
            return Insertion(addSelectionBraces: false, addInputObjectBraces: false)
        case .inputKeys(let input):
            if let arg = input.fields.first(where: { $0.name == selected }) {
                if underlyingInput(arg.type) != nil { return Insertion(addSelectionBraces: false, addInputObjectBraces: true) }
            }
            return Insertion(addSelectionBraces: false, addInputObjectBraces: false)
        case .arguments(_, let field, _, _):
            if let arg = field.args.first(where: { $0.name == selected }) {
                if underlyingInput(arg.type) != nil { return Insertion(addSelectionBraces: false, addInputObjectBraces: true) }
            }
            return Insertion(addSelectionBraces: false, addInputObjectBraces: false)
        default:
            return Insertion(addSelectionBraces: false, addInputObjectBraces: false)
        }
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
        case .arguments(_, let field, let argNameForValue, let used):
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
        case .inputKeys(let input):
            let used = input.usedKeys
            items = input.fields.map { $0.name }.filter { !used.contains($0) && $0.hasPrefix(prefix) }
        case .inputEnumValue(let enumName):
            if let en = schema.enums.first(where: { $0.name == enumName }) {
                items = en.cases.filter { $0.hasPrefix(prefix.uppercased()) }
            } else { items = [] }
        }
        if items.isEmpty { return nil }
        return Suggestions(items: items, replaceStartCol: startCol, replaceEndCol: endCol)
    }

    // MARK: - Context scanning
    private enum Mode {
        case root
        case selection(String)
        case arguments(String, XQField, currentArgName: String?, used: Set<String>)
        case inputKeys(InputFrameSummary)
        case inputEnumValue(String)
    }
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
        struct ArgFrame { let typeName: String; let field: XQField; var usedArgs: Set<String>; var lastColonArgName: String? }
        var argStack: [ArgFrame] = []
        struct InputFrame { let inputName: String; let fields: [XQArgument]; var usedKeys: Set<String>; var lastColonKey: String? }
        var inputStack: [InputFrame] = []
        var lastIdent: String? = nil
        var lastFieldName: String? = nil // last identifier that is a field on current type

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
        func underlyingInput(_ t: XQSTypeRef) -> XQInputObjectType? {
            switch t {
            case .named(let name, _): return inputsByName[name]
            case .list(let of, _, _): return underlyingInput(of)
            }
        }

        func findArg(in typeName: String, field: XQField, name: String) -> XQArgument? {
            field.args.first(where: { $0.name == name })
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
                    if let currentType = typeStack.last, let _ = findField(typeName: currentType, name: s) {
                        lastFieldName = s
                    }
                case .lparen:
                    if let name = lastIdent, let f = findField(typeName: typeStack.last ?? rootType, name: name) {
                        argStack.append(ArgFrame(typeName: typeStack.last ?? rootType, field: f, usedArgs: [], lastColonArgName: nil))
                    }
                case .rparen:
                    _ = argStack.popLast()
                case .lbrace:
                    if !argStack.isEmpty {
                        // First, handle nested input objects inside an existing input frame
                        if let topInput = inputStack.popLast() {
                            if let key = topInput.lastColonKey, let fieldArg = topInput.fields.first(where: { $0.name == key }), let nextInput = underlyingInput(fieldArg.type) {
                                inputStack.append(topInput) // restore before push
                                inputStack.append(InputFrame(inputName: nextInput.name, fields: nextInput.fields, usedKeys: [], lastColonKey: nil))
                                break
                            }
                            inputStack.append(topInput)
                        }
                        // Otherwise, opening input object for an argument (e.g., filter: { ... })
                        if var top = argStack.popLast() {
                            if let argName = top.lastColonArgName, let arg = findArg(in: top.typeName, field: top.field, name: argName), let input = underlyingInput(arg.type) {
                                inputStack.append(InputFrame(inputName: input.name, fields: input.fields, usedKeys: [], lastColonKey: nil))
                                top.lastColonArgName = nil
                            }
                            argStack.append(top)
                        }
                    } else {
                        let candidate = lastFieldName ?? lastIdent
                        if let name = candidate, let f = findField(typeName: typeStack.last ?? rootType, name: name), let obj = underlyingObject(f.type) {
                            typeStack.append(obj)
                        }
                    }
                case .rbrace:
                    if !inputStack.isEmpty { _ = inputStack.popLast() }
                    else if typeStack.count > 1 { _ = typeStack.popLast() }
                case .colon:
                    if var inputTop = inputStack.popLast() {
                        if let key = lastIdent { inputTop.usedKeys.insert(key); inputTop.lastColonKey = key }
                        inputStack.append(inputTop)
                    } else if var top = argStack.popLast() {
                        if let name = lastIdent { top.usedArgs.insert(name); top.lastColonArgName = name }
                        argStack.append(top)
                    }
                case .comma:
                    if var inputTop = inputStack.popLast() { inputTop.lastColonKey = nil; inputStack.append(inputTop) }
                    if var top = argStack.popLast() { top.lastColonArgName = nil; argStack.append(top) }
                case .string:
                    break
                }
            }
        }

        if let inputTop = inputStack.last {
            if let key = inputTop.lastColonKey, let fieldArg = inputTop.fields.first(where: { $0.name == key }) {
                if case let .named(enumName, _) = fieldArg.type, schema.enums.contains(where: { $0.name == enumName }) {
                    return Ctx(mode: .inputEnumValue(enumName))
                }
            }
            return Ctx(mode: .inputKeys(InputFrameSummary(inputName: inputTop.inputName, fields: inputTop.fields, usedKeys: inputTop.usedKeys)))
        }
        if let top = argStack.last {
            return Ctx(mode: .arguments(top.typeName, top.field, currentArgName: top.lastColonArgName, used: top.usedArgs))
        }
        if let typeName = typeStack.last, typeName != rootType {
            return Ctx(mode: .selection(typeName))
        }
        return Ctx(mode: .root)
    }

    private struct InputFrameSummary { let inputName: String; let fields: [XQArgument]; let usedKeys: Set<String> }

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
