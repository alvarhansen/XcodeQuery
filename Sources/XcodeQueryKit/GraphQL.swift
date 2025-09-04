import Foundation
import XcodeProj

// A minimal JSON value to encode dynamic GraphQL results
public enum JSONValue: Encodable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case bool(Bool)
    case number(Double)
    case null

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let dict):
            try container.encode(JSONObject(dict))
        case .array(let arr):
            try container.encode(arr)
        case .string(let s):
            try container.encode(s)
        case .bool(let b):
            try container.encode(b)
        case .number(let n):
            try container.encode(n)
        case .null:
            try container.encodeNil()
        }
    }

    // Helper for building easily
    static func from(_ s: String) -> JSONValue { .string(s) }
    static func from(_ b: Bool) -> JSONValue { .bool(b) }
    static func from<T: BinaryInteger>(_ n: T) -> JSONValue { .number(Double(n)) }
    static func from<T: BinaryFloatingPoint>(_ n: T) -> JSONValue { .number(Double(n)) }

    private struct JSONObject: Encodable {
        let dict: [String: JSONValue]
        init(_ d: [String: JSONValue]) { self.dict = d }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (k, v) in dict { try container.encode(v, forKey: DynamicCodingKey(stringValue: k)!) }
        }
        struct DynamicCodingKey: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { return nil }
        }
    }
}

// MARK: - GraphQL tiny parser

enum GQLError: Error, CustomStringConvertible {
    case parse(String)
    case exec(String)

    var description: String {
        switch self {
        case .parse(let m): return "Parse error: \(m)"
        case .exec(let m): return "Execution error: \(m)"
        }
    }
}

enum GQLValue: Equatable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case enumSymbol(String)
    case object([String: GQLValue])
    case array([GQLValue])
    case null
}

struct GQLField: Equatable {
    let name: String
    let arguments: [String: GQLValue]
    let selection: GQLSelectionSet?
}

struct GQLSelectionSet: Equatable {
    let fields: [GQLField]
}

enum GraphQL {
    static func parseAndExecute(query: String, with exec: GraphQLExecutor) throws -> JSONValue {
        let parser = GQLParser(input: query)
        let sel = try parser.parseDocument()
        return try exec.execute(sel)
    }
}

final class GQLParser {
    private let chars: [Character]
    private var i: Int = 0

    init(input: String) { self.chars = Array(input) }

    func parseDocument() throws -> GQLSelectionSet {
        skipWS()
        let sel = try parseSelectionSet()
        skipWS()
        if !isAtEnd { throw GQLError.parse("Unexpected trailing content at position \(i)") }
        return sel
    }

    private func parseSelectionSet() throws -> GQLSelectionSet {
        try expect("{")
        skipWS()
        var fields: [GQLField] = []
        while !peek("}") {
            let f = try parseField()
            fields.append(f)
            skipWS()
            _ = consumeIf(",") // optional commas
            skipWS()
        }
        try expect("}")
        return GQLSelectionSet(fields: fields)
    }

    private func parseField() throws -> GQLField {
        let name = try parseIdentifier()
        skipWS()
        var args: [String: GQLValue] = [:]
        if consumeIf("(") {
            repeat {
                skipWS()
                let key = try parseIdentifier()
                skipWS(); try expect(":"); skipWS()
                let val = try parseValue()
                args[key] = val
                skipWS()
            } while consumeIf(",")
            try expect(")")
        }
        skipWS()
        var sel: GQLSelectionSet?
        if peek("{") { sel = try parseSelectionSet() }
        return GQLField(name: name, arguments: args, selection: sel)
    }

    private func parseValue() throws -> GQLValue {
        skipWS()
        if consumeIf("\"") { return .string(try parseStringBody()) }
        if consumeIf("{") {
            var obj: [String: GQLValue] = [:]
            skipWS()
            while !peek("}") {
                let key = try parseIdentifier()
                skipWS(); try expect(":"); skipWS()
                let val = try parseValue()
                obj[key] = val
                skipWS(); _ = consumeIf(","); skipWS()
            }
            try expect("}")
            return .object(obj)
        }
        if consumeIf("[") {
            var arr: [GQLValue] = []
            skipWS()
            while !peek("]") {
                let v = try parseValue()
                arr.append(v)
                skipWS(); _ = consumeIf(","); skipWS()
            }
            try expect("]")
            return .array(arr)
        }
        if let ident = try? parseIdentifier() {
            if ident == "true" { return .bool(true) }
            if ident == "false" { return .bool(false) }
            if ident == "null" { return .null }
            // treat as enum symbol or bare string
            return .enumSymbol(ident)
        }
        throw GQLError.parse("Invalid value at position \(i)")
    }

    private func parseIdentifier() throws -> String {
        skipWS()
        guard !isAtEnd else { throw GQLError.parse("Unexpected end of input") }
        var start = i
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        while !isAtEnd {
            let ch = chars[i]
            if String(ch).rangeOfCharacter(from: allowed) != nil {
                i += 1
            } else { break }
        }
        guard i > start else { throw GQLError.parse("Expected identifier at position \(i)") }
        return String(chars[start..<i])
    }

    private func parseStringBody() throws -> String {
        var out = ""
        while !isAtEnd {
            let ch = chars[i]; i += 1
            if ch == "\\" { // escape
                guard !isAtEnd else { throw GQLError.parse("Unterminated escape sequence") }
                let next = chars[i]; i += 1
                switch next {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "n": out.append("\n")
                case "t": out.append("\t")
                default: out.append(next)
                }
            } else if ch == "\"" {
                return out
            } else {
                out.append(ch)
            }
        }
        throw GQLError.parse("Unterminated string literal")
    }

    // helpers
    private var isAtEnd: Bool { i >= chars.count }
    private func peek(_ s: Character) -> Bool { !isAtEnd && chars[i] == s }
    @discardableResult private func consumeIf(_ s: Character) -> Bool { if peek(s) { i += 1; return true } else { return false } }
    private func expect(_ s: Character) throws { guard consumeIf(s) else { throw GQLError.parse("Expected '\\(s)' at position \(i)") } }
    private func skipWS() { while !isAtEnd && chars[i].isWhitespace { i += 1 } }
}

// MARK: - Executor

final class GraphQLExecutor {
    let project: XcodeProj
    let projectPath: String

    init(project: XcodeProj, projectPath: String) {
        self.project = project
        self.projectPath = projectPath
    }

    func execute(_ root: GQLSelectionSet) throws -> JSONValue {
        var out: [String: JSONValue] = [:]
        for f in root.fields {
            out[f.name] = try executeTopField(f)
        }
        return .object(out)
    }

    // Top-level fields
    private func executeTopField(_ f: GQLField) throws -> JSONValue {
        switch f.name {
        case "targets":
            return try resolveTargets(field: f)
        case "target":
            return try resolveTarget(field: f)
        case "dependencies":
            return try resolveDependenciesTop(field: f, reverse: false)
        case "dependents":
            return try resolveDependenciesTop(field: f, reverse: true)
        case "targetSources":
            return try resolveTargetSources(field: f)
        case "targetResources":
            return try resolveTargetResources(field: f)
        case "targetDependencies":
            return try resolveTargetDependencies(field: f)
        case "targetBuildScripts":
            return try resolveTargetBuildScripts(field: f)
        case "targetMembership":
            return try resolveTargetMembership(field: f)
        default:
            throw GQLError.exec("Unknown top-level field: \(f.name)")
        }
    }

    // MARK: - Resolvers

    private func projectTargets() -> [PBXNativeTarget] {
        project.pbxproj.nativeTargets
    }

    private func mapTarget(_ t: PBXNativeTarget) -> Target {
        Target(name: t.name, type: TargetType.from(productType: t.productType))
    }

    private func resolveTargets(field f: GQLField) throws -> JSONValue {
        guard let sel = f.selection else { throw GQLError.exec("targets requires a selection set") }
        var list = projectTargets().map(mapTarget)
        if let typeVal = f.arguments["type"], case let .enumSymbol(sym) = typeVal,
           let tt = TargetType.from(enumSymbol: sym) {
            list = list.filter { $0.type == tt }
        }
        if let filter = f.arguments["filter"], case let .object(obj) = filter {
            list = list.filter { matchTargetFilter($0, obj) }
        }
        list.sort { $0.name < $1.name }
        let arr = try list.map { try resolveTargetObject($0, selection: sel) }
        return .array(arr)
    }

    private func resolveTarget(field f: GQLField) throws -> JSONValue {
        guard let sel = f.selection else { throw GQLError.exec("target requires a selection set") }
        guard let nameVal = f.arguments["name"], case let .string(name) = nameVal else { throw GQLError.exec("target(name: String!) is required") }
        guard let nt = projectTargets().first(where: { $0.name == name }) else { throw GQLError.exec("Unknown target: \(name)") }
        let t = mapTarget(nt)
        return try resolveTargetObject(t, selection: sel)
    }

    private func resolveTargetObject(_ t: Target, selection sel: GQLSelectionSet) throws -> JSONValue {
        var obj: [String: JSONValue] = [:]
        for f in sel.fields {
            switch f.name {
            case "name": obj["name"] = .from(t.name)
            case "type": obj["type"] = .from(t.type.gqlEnum)
            case "dependencies":
                let recursive = (f.arguments["recursive"]?.asBool ?? false)
                let graph = DependencyGraphGQL(project: project)
                let deps = try graph.resolve(base: t.name, reverse: false, recursive: recursive).map(mapTarget)
                var list = deps
                if let filter = f.arguments["filter"], case let .object(objf) = filter {
                    list = list.filter { matchTargetFilter($0, objf) }
                }
                guard let sel2 = f.selection else { throw GQLError.exec("dependencies requires selection set") }
                obj["dependencies"] = .array(try list.map { try resolveTargetObject($0, selection: sel2) })
            case "sources":
                let mode = PathModeGQL.from(arg: f.arguments["pathMode"]) ?? .fileRef
                let paths = try sourceFiles(targetName: t.name, mode: mode)
                var filtered = paths
                if let filter = f.arguments["filter"], case let .object(o) = filter {
                    filtered = filtered.filter { matchString($0, key: "path", obj: o) }
                }
                guard let sel2 = f.selection else { throw GQLError.exec("sources requires selection set") }
                obj["sources"] = .array(filtered.map { path in try! resolveLeafObject(["path": .string(path)], selection: sel2) })
            case "resources":
                let mode = PathModeGQL.from(arg: f.arguments["pathMode"]) ?? .fileRef
                let paths = try resourceFiles(targetName: t.name, mode: mode)
                var filtered = paths
                if let filter = f.arguments["filter"], case let .object(o) = filter {
                    filtered = filtered.filter { matchString($0, key: "path", obj: o) }
                }
                guard let sel2 = f.selection else { throw GQLError.exec("resources requires selection set") }
                obj["resources"] = .array(filtered.map { path in try! resolveLeafObject(["path": .string(path)], selection: sel2) })
            case "buildScripts":
                let all = try buildScripts(targetName: t.name)
                var filtered = all
                if let filter = f.arguments["filter"], case let .object(o) = filter {
                    filtered = filtered.filter { matchBuildScript($0, obj: o) }
                }
                guard let sel2 = f.selection else { throw GQLError.exec("buildScripts requires selection set") }
                obj["buildScripts"] = .array(filtered.map { bs in try! resolveLeafObject([
                    "name": bs.name.map(JSONValue.string) ?? .null,
                    "stage": .string(bs.stage.rawValue.uppercased()),
                    "inputPaths": .array(bs.inputPaths.map(JSONValue.string)),
                    "outputPaths": .array(bs.outputPaths.map(JSONValue.string)),
                    "inputFileListPaths": .array(bs.inputFileListPaths.map(JSONValue.string)),
                    "outputFileListPaths": .array(bs.outputFileListPaths.map(JSONValue.string))
                ], selection: sel2) })
            default:
                throw GQLError.exec("Unknown field on Target: \(f.name)")
            }
        }
        return .object(obj)
    }

    private func resolveDependenciesTop(field f: GQLField, reverse: Bool) throws -> JSONValue {
        guard let sel = f.selection else { throw GQLError.exec("dependencies/dependents requires a selection set") }
        guard let nameVal = f.arguments["name"], case let .string(name) = nameVal else { throw GQLError.exec("name: String! required") }
        let recursive = (f.arguments["recursive"]?.asBool ?? false)
        let graph = DependencyGraphGQL(project: project)
        let listPBX = try graph.resolve(base: name, reverse: reverse, recursive: recursive)
        var list = listPBX.map(mapTarget)
        if let filter = f.arguments["filter"], case let .object(obj) = filter {
            list = list.filter { matchTargetFilter($0, obj) }
        }
        return .array(try list.map { try resolveTargetObject($0, selection: sel) })
    }

    private func resolveTargetSources(field f: GQLField) throws -> JSONValue {
        let mode = PathModeGQL.from(arg: f.arguments["pathMode"]) ?? .fileRef
        var rows: [(target: String, path: String)] = []
        for t in projectTargets() {
            let paths = try sourceFiles(targetName: t.name, mode: mode)
            for p in paths { rows.append((t.name, p)) }
        }
        if let filter = f.arguments["filter"], case let .object(o) = filter {
            rows = rows.filter { row in
                var ok = true
                if o["path"] != nil { ok = ok && matchString(row.path, key: "path", obj: o) }
                if o["target"] != nil { ok = ok && matchString(row.target, key: "target", obj: o) }
                return ok
            }
        }
        guard let sel = f.selection else { throw GQLError.exec("targetSources requires selection") }
        return .array(rows.map { row in try! resolveLeafObject(["target": .string(row.target), "path": .string(row.path)], selection: sel) })
    }

    private func resolveTargetResources(field f: GQLField) throws -> JSONValue {
        let mode = PathModeGQL.from(arg: f.arguments["pathMode"]) ?? .fileRef
        var rows: [(target: String, path: String)] = []
        for t in projectTargets() {
            let paths = try resourceFiles(targetName: t.name, mode: mode)
            for p in paths { rows.append((t.name, p)) }
        }
        if let filter = f.arguments["filter"], case let .object(o) = filter {
            rows = rows.filter { row in
                var ok = true
                if o["path"] != nil { ok = ok && matchString(row.path, key: "path", obj: o) }
                if o["target"] != nil { ok = ok && matchString(row.target, key: "target", obj: o) }
                return ok
            }
        }
        guard let sel = f.selection else { throw GQLError.exec("targetResources requires selection") }
        return .array(rows.map { row in try! resolveLeafObject(["target": .string(row.target), "path": .string(row.path)], selection: sel) })
    }

    private func resolveTargetDependencies(field f: GQLField) throws -> JSONValue {
        let recursive = (f.arguments["recursive"]?.asBool ?? false)
        let graph = DependencyGraphGQL(project: project)
        var rows: [(target: String, dep: Target)] = []
        for t in projectTargets() {
            let deps = try graph.resolve(base: t.name, reverse: false, recursive: recursive).map(mapTarget)
            for d in deps { rows.append((t.name, d)) }
        }
        if let filter = f.arguments["filter"], case let .object(o) = filter {
            rows = rows.filter { matchTargetFilter($0.dep, o) }
        }
        guard let sel = f.selection else { throw GQLError.exec("targetDependencies requires selection") }
        return .array(rows.map { row in try! resolveLeafObject([
            "target": .string(row.target),
            "name": .string(row.dep.name),
            "type": .string(row.dep.type.gqlEnum)
        ], selection: sel) })
    }

    private func resolveTargetBuildScripts(field f: GQLField) throws -> JSONValue {
        var rows: [(target: String, bs: BuildScriptEntry)] = []
        for t in projectTargets() {
            let all = try buildScripts(targetName: t.name)
            for s in all { rows.append((t.name, s)) }
        }
        if let filter = f.arguments["filter"], case let .object(o) = filter {
            rows = rows.filter { matchBuildScript($0.bs, obj: o) }
        }
        guard let sel = f.selection else { throw GQLError.exec("targetBuildScripts requires selection") }
        return .array(rows.map { row in try! resolveLeafObject([
            "target": .string(row.target),
            "name": row.bs.name.map(JSONValue.string) ?? .null,
            "stage": .string(row.bs.stage.rawValue.uppercased()),
            "inputPaths": .array(row.bs.inputPaths.map(JSONValue.string)),
            "outputPaths": .array(row.bs.outputPaths.map(JSONValue.string)),
            "inputFileListPaths": .array(row.bs.inputFileListPaths.map(JSONValue.string)),
            "outputFileListPaths": .array(row.bs.outputFileListPaths.map(JSONValue.string))
        ], selection: sel) })
    }

    private func resolveTargetMembership(field f: GQLField) throws -> JSONValue {
        guard let pathVal = f.arguments["path"], case let .string(path) = pathVal else { throw GQLError.exec("path: String! required") }
        let mode = PathModeGQL.from(arg: f.arguments["pathMode"]) ?? .fileRef
        var owners = Set<String>()
        for t in projectTargets() {
            let list = try sourceFiles(targetName: t.name, mode: mode)
            if list.contains(path) { owners.insert(t.name) }
        }
        guard let sel = f.selection else { throw GQLError.exec("targetMembership requires selection") }
        return try resolveLeafObject(["path": .string(path), "targets": .array(Array(owners).sorted().map(JSONValue.string))], selection: sel)
    }

    // Leaf object selection projection helper
    private func resolveLeafObject(_ base: [String: JSONValue], selection sel: GQLSelectionSet) throws -> JSONValue {
        var out: [String: JSONValue] = [:]
        for f in sel.fields {
            if let v = base[f.name] { out[f.name] = v } else { throw GQLError.exec("Unknown field: \(f.name)") }
        }
        return .object(out)
    }

    // MARK: - Filters and enums

    private func matchTargetFilter(_ t: Target, _ obj: [String: GQLValue]) -> Bool {
        for (k, v) in obj {
            switch k {
            case "name": if !matchString(t.name, value: v) { return false }
            case "type": if case let .enumSymbol(sym) = v, let tt = TargetType.from(enumSymbol: sym) { if t.type != tt { return false } } else { return false }
            default: return false
            }
        }
        return true
    }

    private func matchString(_ s: String, key: String = "", obj: [String: GQLValue]) -> Bool {
        // obj is { path: { eq/regex/prefix/suffix/contains } } or direct { eq: ..., ... }
        if let nested = obj[key] { return matchString(s, value: nested) }
        return matchString(s, value: .object(obj))
    }

    private func matchString(_ s: String, value: GQLValue) -> Bool {
        guard case let .object(o) = value else { return false }
        for (k, v) in o {
            switch k {
            case "eq": if case let .string(val) = v { if s != val { return false } } else { return false }
            case "regex": if case let .string(pat) = v { if (try? NSRegularExpression(pattern: pat)).map({ re in re.firstMatch(in: s, range: NSRange(location: 0, length: s.utf16.count)) != nil }) != true { return false } } else { return false }
            case "prefix": if case let .string(val) = v { if !s.hasPrefix(val) { return false } } else { return false }
            case "suffix": if case let .string(val) = v { if !s.hasSuffix(val) { return false } } else { return false }
            case "contains": if case let .string(val) = v { if !s.contains(val) { return false } } else { return false }
            default: return false
            }
        }
        return true
    }

    private func matchBuildScript(_ s: BuildScriptEntry, obj: [String: GQLValue]) -> Bool {
        for (k, v) in obj {
            switch k {
            case "stage": if case let .enumSymbol(sym) = v { if s.stage.rawValue.uppercased() != sym.uppercased() { return false } } else { return false }
            case "name": if !matchString(s.name ?? "", value: v) { return false }
            case "target": if !matchString(s.target, value: v) { return false }
            default: return false
            }
        }
        return true
    }

    // MARK: - Data collection helpers

    enum PathModeGQL { case fileRef, absolute, normalized
        static func from(arg: GQLValue?) -> PathModeGQL? {
            guard let arg else { return nil }
            switch arg {
            case .enumSymbol(let s):
                switch s.uppercased() {
                case "FILE_REF": return .fileRef
                case "ABSOLUTE": return .absolute
                case "NORMALIZED": return .normalized
                default: return nil
                }
            default: return nil
            }
        }
    }

    private func sourceFiles(targetName: String, mode: PathModeGQL) throws -> [String] {
        guard let nt = projectTargets().first(where: { $0.name == targetName }) else { throw GQLError.exec("Unknown target: \(targetName)") }
        let projDirURL = URL(fileURLWithPath: projectPath).deletingLastPathComponent()
        let projectRoot = projDirURL.path
        let stdProjectRoot = URL(fileURLWithPath: projectRoot).standardizedFileURL.path
        var results: [String] = []
        for phase in nt.buildPhases.compactMap({ $0 as? PBXSourcesBuildPhase }) {
            for bf in phase.files ?? [] {
                if let fr = bf.file as? PBXFileReference {
                    let ref = fr.path ?? fr.name ?? ""
                    switch mode {
                    case .fileRef:
                        results.append(ref)
                    case .absolute:
                        if let fullStr = (try? fr.fullPath(sourceRoot: projectRoot)) ?? nil {
                            results.append(URL(fileURLWithPath: fullStr).standardizedFileURL.path)
                        } else if ref.hasPrefix("/") {
                            results.append(URL(fileURLWithPath: ref).standardizedFileURL.path)
                        } else {
                            results.append(projDirURL.appendingPathComponent(ref).standardizedFileURL.path)
                        }
                    case .normalized:
                        if let fullStr = (try? fr.fullPath(sourceRoot: projectRoot)) ?? nil {
                            let stdFull = URL(fileURLWithPath: fullStr).standardizedFileURL.path
                            if stdFull.hasPrefix(stdProjectRoot + "/") {
                                results.append(String(stdFull.dropFirst(stdProjectRoot.count + 1)))
                            } else {
                                results.append(stdFull)
                            }
                        } else if ref.hasPrefix("/") {
                            let stdRef = URL(fileURLWithPath: ref).standardizedFileURL.path
                            if stdRef.hasPrefix(stdProjectRoot + "/") {
                                results.append(String(stdRef.dropFirst(stdProjectRoot.count + 1)))
                            } else {
                                results.append(stdRef)
                            }
                        } else {
                            let rel = URL(fileURLWithPath: ref, relativeTo: projDirURL).standardizedFileURL.path
                            if rel.hasPrefix(stdProjectRoot + "/") {
                                results.append(String(rel.dropFirst(stdProjectRoot.count + 1)))
                            } else {
                                results.append(ref)
                            }
                        }
                    }
                }
            }
        }
        return results
    }

    private func resourceFiles(targetName: String, mode: PathModeGQL) throws -> [String] {
        guard let nt = projectTargets().first(where: { $0.name == targetName }) else { throw GQLError.exec("Unknown target: \(targetName)") }
        let projDirURL = URL(fileURLWithPath: projectPath).deletingLastPathComponent()
        let projectRoot = projDirURL.path
        let stdProjectRoot = URL(fileURLWithPath: projectRoot).standardizedFileURL.path
        var results: [String] = []
        for p in nt.buildPhases.compactMap({ $0 as? PBXResourcesBuildPhase }) {
            for f in p.files ?? [] {
                if let fr = f.file as? PBXFileReference {
                    let ref = fr.path ?? fr.name ?? ""
                    switch mode {
                    case .fileRef:
                        results.append(ref)
                    case .absolute:
                        if let fullStr = (try? fr.fullPath(sourceRoot: projectRoot)) ?? nil {
                            results.append(URL(fileURLWithPath: fullStr).standardizedFileURL.path)
                        } else if ref.hasPrefix("/") {
                            results.append(URL(fileURLWithPath: ref).standardizedFileURL.path)
                        } else {
                            results.append(projDirURL.appendingPathComponent(ref).standardizedFileURL.path)
                        }
                    case .normalized:
                        if let fullStr = (try? fr.fullPath(sourceRoot: projectRoot)) ?? nil {
                            let stdFull = URL(fileURLWithPath: fullStr).standardizedFileURL.path
                            if stdFull.hasPrefix(stdProjectRoot + "/") {
                                results.append(String(stdFull.dropFirst(stdProjectRoot.count + 1)))
                            } else {
                                results.append(stdFull)
                            }
                        } else if ref.hasPrefix("/") {
                            let stdRef = URL(fileURLWithPath: ref).standardizedFileURL.path
                            if stdRef.hasPrefix(stdProjectRoot + "/") {
                                results.append(String(stdRef.dropFirst(stdProjectRoot.count + 1)))
                            } else {
                                results.append(stdRef)
                            }
                        } else {
                            let rel = URL(fileURLWithPath: ref, relativeTo: projDirURL).standardizedFileURL.path
                            if rel.hasPrefix(stdProjectRoot + "/") {
                                results.append(String(rel.dropFirst(stdProjectRoot.count + 1)))
                            } else {
                                results.append(ref)
                            }
                        }
                    }
                }
            }
        }
        return results
    }

    private func buildScripts(targetName: String) throws -> [BuildScriptEntry] {
        guard let nt = projectTargets().first(where: { $0.name == targetName }) else { throw GQLError.exec("Unknown target: \(targetName)") }
        let phases = nt.buildPhases
        let sourcesIndex = phases.firstIndex { $0 is PBXSourcesBuildPhase }
        var result: [BuildScriptEntry] = []
        for (idx, phase) in phases.enumerated() {
            guard let script = phase as? PBXShellScriptBuildPhase else { continue }
            let stage: BuildScriptEntry.Stage = (sourcesIndex != nil && idx < sourcesIndex!) ? .pre : .post
            let entry = BuildScriptEntry(
                target: nt.name,
                name: script.name,
                stage: stage,
                inputPaths: script.inputPaths,
                outputPaths: script.outputPaths,
                inputFileListPaths: script.inputFileListPaths ?? [],
                outputFileListPaths: script.outputFileListPaths ?? []
            )
            result.append(entry)
        }
        return result
    }
}

// MARK: - Helpers

private extension GQLValue {
    var asBool: Bool? { if case let .bool(b) = self { return b } else { return nil } }
}

private extension TargetType {
    static func from(enumSymbol: String) -> TargetType? {
        switch enumSymbol.uppercased() {
        case "APP": return .app
        case "FRAMEWORK": return .framework
        case "STATIC_LIBRARY": return .staticLibrary
        case "DYNAMIC_LIBRARY": return .dynamicLibrary
        case "UNIT_TEST": return .unitTest
        case "UI_TEST": return .uiTest
        case "EXTENSION": return .extensionKit
        case "BUNDLE": return .bundle
        case "COMMAND_LINE_TOOL": return .commandLineTool
        case "WATCH_APP": return .watchApp
        case "WATCH2_APP": return .watch2App
        case "TV_APP": return .tvApp
        case "OTHER": return .other
        default: return nil
        }
    }
    var gqlEnum: String {
        switch self {
        case .app: return "APP"
        case .framework: return "FRAMEWORK"
        case .staticLibrary: return "STATIC_LIBRARY"
        case .dynamicLibrary: return "DYNAMIC_LIBRARY"
        case .unitTest: return "UNIT_TEST"
        case .uiTest: return "UI_TEST"
        case .extensionKit: return "EXTENSION"
        case .bundle: return "BUNDLE"
        case .commandLineTool: return "COMMAND_LINE_TOOL"
        case .watchApp: return "WATCH_APP"
        case .watch2App: return "WATCH2_APP"
        case .tvApp: return "TV_APP"
        case .other: return "OTHER"
        }
    }
}

// Simple dependency resolver for GraphQL
private final class DependencyGraphGQL {
    let targets: [PBXNativeTarget]
    private let byName: [String: PBXNativeTarget]
    private let depsByName: [String: [PBXNativeTarget]]
    private let revByName: [String: [PBXNativeTarget]]

    init(project: XcodeProj) {
        let list = project.pbxproj.nativeTargets
        self.targets = list
        self.byName = Dictionary(uniqueKeysWithValues: list.map { ($0.name, $0) })
        var forward: [String: [PBXNativeTarget]] = [:]
        var reverse: [String: [PBXNativeTarget]] = [:]
        for t in list {
            let deps = t.dependencies.compactMap { $0.target as? PBXNativeTarget }
            forward[t.name] = deps
            for d in deps { reverse[d.name, default: []].append(t) }
        }
        self.depsByName = forward
        self.revByName = reverse
    }

    func resolve(base: String, reverse: Bool, recursive: Bool) throws -> [PBXNativeTarget] {
        guard byName[base] != nil else { throw GQLError.exec("Unknown target: \(base)") }
        let edges = reverse ? revByName : depsByName
        if !recursive { return edges[base] ?? [] }
        return traverse(start: base, edges: edges)
    }

    private func traverse(start: String, edges: [String: [PBXNativeTarget]]) -> [PBXNativeTarget] {
        var visited = Set<String>()
        var queue = [String]()
        var order: [PBXNativeTarget] = []
        func enqueue(_ name: String) {
            guard !visited.contains(name) else { return }
            visited.insert(name)
            if let neighbors = edges[name] {
                for n in neighbors { queue.append(n.name) }
                order.append(contentsOf: neighbors)
            }
        }
        enqueue(start)
        while let next = queue.first { queue.removeFirst(); enqueue(next) }
        var seen = Set<String>()
        var unique: [PBXNativeTarget] = []
        for t in order where !seen.contains(t.name) {
            seen.insert(t.name)
            if t.name != start { unique.append(t) }
        }
        return unique
    }
}
