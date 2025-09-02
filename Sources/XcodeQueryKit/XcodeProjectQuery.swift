import Foundation
import XcodeProj

public class XcodeProjectQuery {
    
    public enum Error: Swift.Error {
        case invalidQuery(String)
    }
    
    private let projectPath: String
    
    public init(projectPath: String) {
        self.projectPath = projectPath
    }
    
    public func evaluate(query: String) throws -> AnyEncodable {
        let proj = try XcodeProj(pathString: projectPath)

        // Build base targets model
        let targets: [Target] = proj.pbxproj.nativeTargets.map { t in
            Target(name: t.name, type: TargetType.from(productType: t.productType))
        }

        // Support queries:
        // - .targets
        // - .targets[]
        // - .targets[] | filter(.name.hasSuffix("Tests"))
        // - .targets[] | filter(.name | hasSuffix("Tests"))
        // - .targets[] | filter(.type == .unitTest)
        // - .targets[] | filter(...) | dependencies(recursive: true)
        // - .targets[] | dependencies
        // - .sources("TargetName")
        // - .targets[] | filter(...) | sources
        // - .owners("path")
        // - .filesWithMultipleTargets
        // - .filesWithoutTargets
        // - .buildScripts("TargetName")
        // - .targets[] | buildScripts
        if query == ".targets" || query == ".targets[]" {
            return AnyEncodable(targets)
        }

        if let pipeline = Self.parseTargetsPipeline(query) {
            // start with all targets
            var current = targets
            if let pred = pipeline.filterPredicate {
                current = try Self.apply(predicate: pred, to: current)
            }
            if let op = pipeline.operation {
                switch op.kind {
                case .sources:
                    var uniq = Set<String>()
                    var out: [SourceEntry] = []
                    for t in current {
                        if let nt = proj.pbxproj.nativeTargets.first(where: { $0.name == t.name }) {
                            for s in Self.sourceFiles(for: nt, mode: op.pathMode ?? .fileRef, projectPath: projectPath) {
                                let key = "\(t.name)\n\(s)"
                                if uniq.insert(key).inserted {
                                    out.append(SourceEntry(target: t.name, path: s))
                                }
                            }
                        }
                    }
                    return AnyEncodable(out.sorted { $0.target == $1.target ? $0.path < $1.path : $0.target < $1.target })
                case .targetMembership:
                    // Given selected targets, compute their sources then map to owners
                    let index = FileIndex(project: proj, projectPath: projectPath)
                    var uniq = [String: Set<String>]()
                    for t in current {
                        if let nt = proj.pbxproj.nativeTargets.first(where: { $0.name == t.name }) {
                            for s in Self.sourceFiles(for: nt, mode: op.pathMode ?? .fileRef, projectPath: projectPath) {
                                uniq[s, default: []].formUnion(index.owners(forPath: s, mode: op.pathMode ?? .fileRef))
                            }
                        }
                    }
                    let out = uniq.map { OwnerEntry(path: $0.key, targets: Array($0.value).sorted()) }
                    return AnyEncodable(out.sorted { $0.path < $1.path })
                case .buildScripts:
                    var scripts: [BuildScriptEntry] = []
                    for t in current {
                        if let nt = proj.pbxproj.nativeTargets.first(where: { $0.name == t.name }) {
                            scripts.append(contentsOf: Self.collectBuildScripts(for: nt))
                        }
                    }
                    if let sp = pipeline.scriptsFilter {
                        scripts = try Self.applyScriptPredicate(sp, to: scripts)
                    }
                    return AnyEncodable(scripts)
                default:
                    let graph = DependencyGraph(project: proj)
                    // union dependencies/dependents for all selected targets
                    var byName: [String: Target] = [:]
                    for t in current {
                        let baseName = t.name
                        let resolved: [PBXNativeTarget]
                        switch op.kind {
                        case .dependencies:
                            resolved = (try? graph.dependencies(of: baseName, recursive: op.recursive)) ?? []
                        case .dependents:
                            resolved = (try? graph.dependents(of: baseName, recursive: op.recursive)) ?? []
                        case .sources, .targetMembership, .buildScripts:
                            resolved = [] // unreachable
                        }
                        for r in resolved {
                            let mapped = Target(name: r.name, type: TargetType.from(productType: r.productType))
                            byName[mapped.name] = mapped
                        }
                    }
                    return AnyEncodable(Array(byName.values).sorted { $0.name < $1.name })
                }
            } else {
                return AnyEncodable(current)
            }
        }

        if let pred = Self.extractFilterPredicate(from: query) {
            let filtered = try Self.apply(predicate: pred, to: targets)
            return AnyEncodable(filtered)
        }

        if let call = Self.extractDependenciesCall(from: query) {
            let graph = DependencyGraph(project: proj)
            let results = try graph.dependencies(of: call.name, recursive: call.recursive)
                .map { t in Target(name: t.name, type: TargetType.from(productType: t.productType)) }
            return AnyEncodable(results)
        }

        if let call = Self.extractDependentsCall(from: query) {
            let graph = DependencyGraph(project: proj)
            let results = try graph.dependents(of: call.name, recursive: call.recursive)
                .map { t in Target(name: t.name, type: TargetType.from(productType: t.productType)) }
            return AnyEncodable(results)
        }

        if let sc = Self.extractSourcesCall(from: query) {
            guard let base = proj.pbxproj.nativeTargets.first(where: { $0.name == sc.name }) else {
                throw Error.invalidQuery("Unknown target: \(sc.name)")
            }
            let paths = Self.sourceFiles(for: base, mode: sc.mode, projectPath: projectPath)
            let out = paths.map { SourceEntry(target: base.name, path: $0) }
            return AnyEncodable(out)
        }

        if let oc = Self.extractTargetMembershipCall(from: query) {
            let index = FileIndex(project: proj, projectPath: projectPath)
            let owners = index.owners(forPath: oc.path, mode: oc.mode)
            return AnyEncodable(OwnerEntry(path: oc.path, targets: Array(owners).sorted()))
        }

        if let bc = Self.extractBuildScriptsCall(from: query) {
            guard let base = proj.pbxproj.nativeTargets.first(where: { $0.name == bc }) else {
                throw Error.invalidQuery("Unknown target: \(bc)")
            }
            return AnyEncodable(Self.collectBuildScripts(for: base))
        }

        throw Error.invalidQuery(query)
    }
}

struct Target: Codable {
    var name: String
    var type: TargetType
}

struct SourceEntry: Codable, Equatable {
    var target: String
    var path: String
}

struct OwnerEntry: Codable, Equatable {
    var path: String
    var targets: [String]
}

struct BuildScriptEntry: Codable, Equatable {
    var target: String
    var name: String?
    var stage: Stage
    var inputPaths: [String]
    var outputPaths: [String]
    var inputFileListPaths: [String]
    var outputFileListPaths: [String]

    enum Stage: String, Codable {
        case pre
        case post
    }
}

enum TargetType: String, Codable, Equatable {
    case app
    case framework
    case staticLibrary
    case dynamicLibrary
    case unitTest
    case uiTest
    case extensionKit
    case bundle
    case commandLineTool
    case watchApp
    case watch2App
    case tvApp
    case other

    static func from(productType: PBXProductType?) -> TargetType {
        guard let productType else { return .other }
        switch productType {
        case .application: return .app
        case .framework: return .framework
        case .staticLibrary: return .staticLibrary
        case .dynamicLibrary: return .dynamicLibrary
        case .unitTestBundle: return .unitTest
        case .uiTestBundle: return .uiTest
        case .appExtension: return .extensionKit
        case .bundle: return .bundle
        case .commandLineTool: return .commandLineTool
        case .watchApp: return .watchApp
        case .watch2App: return .watch2App
        default:
            return .other
        }
    }
}

public struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    public init<T: Encodable>(_ wrapped: T) {
        self._encode = wrapped.encode
    }

    public func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - Simple query parsing

extension XcodeProjectQuery {
    struct PipelineOp {
        enum Kind { case dependencies, dependents, sources, targetMembership, buildScripts }
        let kind: Kind
        let recursive: Bool
        let pathMode: PathMode?
        init(kind: Kind, recursive: Bool = false, pathMode: PathMode? = nil) {
            self.kind = kind
            self.recursive = recursive
            self.pathMode = pathMode
        }
    }

    enum PathMode: String {
        case fileRef
        case absolute
        case normalized
    }
    private static func extractFilterPredicate(from query: String) -> String? {
        // Accept forms like: ".targets[] | filter(<predicate>)"
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(".targets[]") else { return nil }
        let remainder = trimmed.dropFirst(".targets[]".count)
        // Split into pipeline tokens separated by '|'
        let tokens = remainder.split(separator: "|", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = tokens.first, first.hasPrefix("filter("), first.hasSuffix(")") else { return nil }
        let inner = first.dropFirst("filter(".count).dropLast()
        return String(inner).trimmingCharacters(in: .whitespaces)
    }

    // Parse a pipeline that starts with .targets[] and optionally includes filter and dependencies/dependents
    fileprivate static func parseTargetsPipeline(_ query: String) -> (filterPredicate: String?, operation: PipelineOp?, scriptsFilter: String?)? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(".targets[]") else { return nil }
        let remainder = trimmed.dropFirst(".targets[]".count)
        if remainder.trimmingCharacters(in: .whitespaces).isEmpty { return (nil, nil, nil) }
        let tokens = remainder.split(separator: "|", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
        var filterPred: String?
        var scriptsFilter: String?
        var op: PipelineOp?
        var lastKind: PipelineOp.Kind?
        var lastSourcesMode: PathMode?
        for tok in tokens {
            if tok.hasPrefix("filter("), tok.hasSuffix(")") {
                let inner = tok.dropFirst("filter(".count).dropLast()
                if lastKind == .buildScripts {
                    scriptsFilter = String(inner).trimmingCharacters(in: .whitespaces)
                } else {
                    filterPred = String(inner).trimmingCharacters(in: .whitespaces)
                }
            } else if tok.hasPrefix("dependencies") {
                let recursive = parseOptionalRecursive(tok)
                op = PipelineOp(kind: .dependencies, recursive: recursive)
                lastKind = .dependencies
            } else if tok.hasPrefix("dependents") || tok.hasPrefix("reverseDependencies") || tok.hasPrefix("rdeps") {
                let recursive = parseOptionalRecursive(tok)
                op = PipelineOp(kind: .dependents, recursive: recursive)
                lastKind = .dependents
            } else if tok == "sources" || tok.hasPrefix("sources(") {
                let mode = parseSourcesMode(tok)
                lastSourcesMode = mode ?? lastSourcesMode
                op = PipelineOp(kind: .sources, recursive: false, pathMode: lastSourcesMode)
                lastKind = .sources
            } else if tok == "targetMembership" || tok.hasPrefix("targetMembership(") {
                let mode = parseSourcesMode(tok)
                op = PipelineOp(kind: .targetMembership, recursive: false, pathMode: mode ?? lastSourcesMode)
                lastKind = .targetMembership
            } else if tok == "buildScripts" {
                op = PipelineOp(kind: .buildScripts)
                lastKind = .buildScripts
            } else if tok.isEmpty { continue } else {
                // unknown token, bail
                return nil
            }
        }
        return (filterPred, op, scriptsFilter)
    }

    // Extracts a single string argument from a function-like query, e.g.
    // .dependencies("App") -> returns "App"
    // .dependencies(App)   -> returns "App"
    private static func extractFunctionArg(from query: String, function: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(function + "(") && trimmed.hasSuffix(")") else { return nil }
        let start = trimmed.index(trimmed.startIndex, offsetBy: function.count + 1)
        let inner = trimmed[start..<trimmed.index(before: trimmed.endIndex)]
        let arg = inner.trimmingCharacters(in: .whitespaces)
        if arg.hasPrefix("\"") && arg.hasSuffix("\"") {
            return String(arg.dropFirst().dropLast())
        } else {
            return String(arg)
        }
    }

    private static func apply(predicate: String, to targets: [Target]) throws -> [Target] {
        // Support:
        // - .type == .unitTest
        // - .name == "Text"
        // - .name.hasSuffix("Tests")
        // - .name | hasSuffix("Tests")
        if predicate.hasPrefix(".type == .") {
            let value = predicate.replacingOccurrences(of: ".type == .", with: "")
            if let t = TargetType(shortName: value) {
                return targets.filter { $0.type == t }
            }
        }

        if predicate.hasPrefix(".name == ") {
            let rest = predicate.dropFirst(".name == ".count).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("\"") && rest.hasSuffix("\"") && rest.count >= 2 {
                let val = String(rest.dropFirst().dropLast())
                return targets.filter { $0.name == val }
            }
        }

        if let suffix = extractHasSuffix(from: predicate) {
            return targets.filter { $0.name.hasSuffix(suffix) }
        }

        throw Error.invalidQuery(predicate)
    }

    private static func applyScriptPredicate(_ predicate: String, to scripts: [BuildScriptEntry]) throws -> [BuildScriptEntry] {
        // Support:
        // - .stage == .pre | .post
        // - .name == "Text"
        // - .name.hasPrefix("Text") or .name | hasPrefix("Text")
        // - .name.hasSuffix("Text") or .name | hasSuffix("Text")
        let trimmed = predicate.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(".stage == .") {
            let value = trimmed.replacingOccurrences(of: ".stage == .", with: "")
            switch value {
            case "pre": return scripts.filter { $0.stage == .pre }
            case "post": return scripts.filter { $0.stage == .post }
            default: throw Error.invalidQuery(predicate)
            }
        }
        if trimmed.hasPrefix(".name == ") {
            let rest = trimmed.dropFirst(".name == ".count).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix("\"") && rest.hasSuffix("\"") && rest.count >= 2 {
                let val = String(rest.dropFirst().dropLast())
                return scripts.filter { ($0.name ?? "") == val }
            }
        }
        if let pfx = extractNameHasPrefix(from: predicate) {
            return scripts.filter { ($0.name ?? "").hasPrefix(pfx) }
        }
        if let sfx = extractHasSuffix(from: predicate) {
            return scripts.filter { ($0.name ?? "").hasSuffix(sfx) }
        }
        throw Error.invalidQuery(predicate)
    }

    fileprivate static func sourceFiles(for target: PBXNativeTarget, mode: PathMode, projectPath: String) -> [String] {
        let phases = target.buildPhases.compactMap { $0 as? PBXSourcesBuildPhase }
        var results: [String] = []
        let projDirURL = URL(fileURLWithPath: projectPath).deletingLastPathComponent()
        let projectRoot = projDirURL.path
        let stdProjectRoot = URL(fileURLWithPath: projectRoot).standardizedFileURL.path
        for p in phases {
            for f in p.files ?? [] {
                if let fr = f.file as? PBXFileReference {
                    let ref = fr.path ?? fr.name ?? ""
                    switch mode {
                    case .fileRef:
                        results.append(ref)
                    case .absolute:
                        if let fullStr = (try? fr.fullPath(sourceRoot: projectRoot)) ?? nil {
                            let stdFull = URL(fileURLWithPath: fullStr).standardizedFileURL.path
                            results.append(stdFull)
                        } else if ref.hasPrefix("/") {
                            results.append(URL(fileURLWithPath: ref).standardizedFileURL.path)
                        } else {
                            // Assume relative to project root
                            let abs = projDirURL.appendingPathComponent(ref).standardizedFileURL.path
                            results.append(abs)
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
                            // Already relative; assume relative to project root
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

    fileprivate static func collectBuildScripts(for target: PBXNativeTarget) -> [BuildScriptEntry] {
        let phases = target.buildPhases
        let sourcesIndex = phases.firstIndex { $0 is PBXSourcesBuildPhase }
        var result: [BuildScriptEntry] = []
        for (idx, phase) in phases.enumerated() {
            guard let script = phase as? PBXShellScriptBuildPhase else { continue }
            let stage: BuildScriptEntry.Stage = (sourcesIndex != nil && idx < sourcesIndex!) ? .pre : .post
            let entry = BuildScriptEntry(
                target: target.name,
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

    private static func extractHasSuffix(from predicate: String) -> String? {
        // Matches ".name.hasSuffix("TEXT")" or ".name | hasSuffix("TEXT")"
        let trimmed = predicate.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(".name") else { return nil }
        let remainder = trimmed.dropFirst(".name".count).trimmingCharacters(in: .whitespaces)
        let callPart: Substring
        if remainder.hasPrefix("|") {
            // pipeline form: | hasSuffix("...")
            let afterPipe = remainder.dropFirst().trimmingCharacters(in: .whitespaces)
            callPart = Substring(afterPipe)
        } else if remainder.hasPrefix(".") {
            // dot-call form: .hasSuffix("...")
            callPart = remainder.dropFirst()
        } else {
            return nil
        }
        guard callPart.hasPrefix("hasSuffix(\"") && callPart.hasSuffix("\")") else { return nil }
        let inner = callPart.dropFirst("hasSuffix(\"".count).dropLast("\")".count)
        return String(inner)
    }

    private static func extractNameHasPrefix(from predicate: String) -> String? {
        let trimmed = predicate.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(".name") else { return nil }
        let remainder = trimmed.dropFirst(".name".count).trimmingCharacters(in: .whitespaces)
        let callPart: Substring
        if remainder.hasPrefix("|") {
            let afterPipe = remainder.dropFirst().trimmingCharacters(in: .whitespaces)
            callPart = Substring(afterPipe)
        } else if remainder.hasPrefix(".") {
            callPart = remainder.dropFirst()
        } else {
            return nil
        }
        guard callPart.hasPrefix("hasPrefix(\"") && callPart.hasSuffix("\")") else { return nil }
        let inner = callPart.dropFirst("hasPrefix(\"".count).dropLast("\")".count)
        return String(inner)
    }
}

private extension TargetType {
    init?(shortName: String) {
        switch shortName {
        case "app": self = .app
        case "framework": self = .framework
        case "staticLibrary": self = .staticLibrary
        case "dynamicLibrary": self = .dynamicLibrary
        case "unitTest": self = .unitTest
        case "uiTest": self = .uiTest
        case "extension": self = .extensionKit
        case "bundle": self = .bundle
        case "commandLineTool": self = .commandLineTool
        case "watchApp": self = .watchApp
        case "watch2App": self = .watch2App
        case "tvApp": self = .tvApp
        default: return nil
        }
    }
}

// MARK: - Extended parsing for function calls

extension XcodeProjectQuery {
    private static func parseOptionalRecursive(_ token: String) -> Bool {
        // token may be "dependencies" or "dependencies(recursive: true)"
        guard let open = token.firstIndex(of: "("), token.hasSuffix(")") else { return false }
        let inner = token[token.index(after: open)..<token.index(before: token.endIndex)]
        return parseRecursiveFlag(String(inner))
    }
    fileprivate static func extractDependenciesCall(from query: String) -> (name: String, recursive: Bool)? {
        extractFunctionArgs(from: query, function: ".dependencies")
    }

    fileprivate static func extractDependentsCall(from query: String) -> (name: String, recursive: Bool)? {
        if let v = extractFunctionArgs(from: query, function: ".dependents") { return v }
        if let v = extractFunctionArgs(from: query, function: ".reverseDependencies") { return v }
        if let v = extractFunctionArgs(from: query, function: ".rdeps") { return v }
        return nil
    }

    fileprivate static func extractSourcesCall(from query: String) -> (name: String, mode: PathMode)? {
        // Accept: .sources("Name") or .sources("Name", pathMode: "absolute")
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(".sources(") && trimmed.hasSuffix(")") else { return nil }
        let inner = trimmed.dropFirst(".sources(".count).dropLast()
        let items = inner.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = items.first else { return nil }
        let name = stripQuotes(String(first).trimmingCharacters(in: .whitespaces))
        var mode: PathMode = .fileRef
        if items.count == 2 {
            let arg = String(items[1]).trimmingCharacters(in: .whitespaces)
            if let parsed = parsePathMode(from: arg) { mode = parsed }
        }
        return (name: name, mode: mode)
    }

    fileprivate static func extractTargetMembershipCall(from query: String) -> (path: String, mode: PathMode)? {
        // .targetMembership("<path>") or .targetMembership("<path>", pathMode: "normalized")
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(".targetMembership(") && trimmed.hasSuffix(")") else { return nil }
        let inner = trimmed.dropFirst(".targetMembership(".count).dropLast()
        let items = inner.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = items.first else { return nil }
        let path = stripQuotes(String(first).trimmingCharacters(in: .whitespaces))
        var mode: PathMode = .fileRef
        if items.count == 2 {
            let arg = String(items[1]).trimmingCharacters(in: .whitespaces)
            if let parsed = parsePathMode(from: arg) { mode = parsed }
        }
        return (path: path, mode: mode)
    }

    private static func parseSourcesMode(_ token: String) -> PathMode? {
        // token is either "sources" or "sources(pathMode: "...")"
        guard let open = token.firstIndex(of: "(") else { return nil }
        guard token.hasSuffix(")") else { return nil }
        let inner = token[token.index(after: open)..<token.index(before: token.endIndex)]
        return parsePathMode(from: String(inner))
    }

    private static func parsePathMode(from arg: String) -> PathMode? {
        // Accept pathMode: "absolute" | "normalized" | "fileRef"
        let cleaned: String
        if let range = arg.range(of: "pathMode") {
            let rhs = arg[range.upperBound...]
            if let eq = rhs.firstIndex(where: { $0 == ":" || $0 == "=" }) {
                let value = rhs[rhs.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                cleaned = stripQuotes(String(value))
            } else {
                return nil
            }
        } else {
            cleaned = stripQuotes(arg.trimmingCharacters(in: .whitespaces))
        }
        return PathMode(rawValue: cleaned)
    }

    fileprivate static func extractBuildScriptsCall(from query: String) -> String? {
        extractFunctionArg(from: query, function: ".buildScripts")
    }

    private static func extractFunctionArgs(from query: String, function: String) -> (name: String, recursive: Bool)? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(function + "(") && trimmed.hasSuffix(")") else { return nil }
        let start = trimmed.index(trimmed.startIndex, offsetBy: function.count + 1)
        let inner = trimmed[start..<trimmed.index(before: trimmed.endIndex)]
        let items = inner.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = items.first else { return nil }
        let name = stripQuotes(String(first).trimmingCharacters(in: .whitespaces))
        var recursive = false
        if items.count == 2 {
            let opt = String(items[1]).trimmingCharacters(in: .whitespaces)
            recursive = parseRecursiveFlag(opt)
        }
        return (name: name, recursive: recursive)
    }

    private static func stripQuotes(_ s: String) -> String {
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    private static func parseRecursiveFlag(_ s: String) -> Bool {
        let lower = s.lowercased()
        if lower == "recursive" { return true }
        if lower.contains("recursive:") || lower.contains("recursive=") {
            return lower.contains("true")
        }
        return false
    }
}

// MARK: - Dependency graph utilities

private final class DependencyGraph {
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
            for d in deps {
                reverse[d.name, default: []].append(t)
            }
        }
        self.depsByName = forward
        self.revByName = reverse
    }

    func dependencies(of name: String, recursive: Bool) throws -> [PBXNativeTarget] {
        guard byName[name] != nil else { throw XcodeProjectQuery.Error.invalidQuery("Unknown target: \(name)") }
        if !recursive { return depsByName[name] ?? [] }
        return traverse(start: name, edges: depsByName)
    }

    func dependents(of name: String, recursive: Bool) throws -> [PBXNativeTarget] {
        guard byName[name] != nil else { throw XcodeProjectQuery.Error.invalidQuery("Unknown target: \(name)") }
        if !recursive { return revByName[name] ?? [] }
        return traverse(start: name, edges: revByName)
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

// MARK: - File index utilities

private final class FileIndex {
    private let proj: XcodeProj
    private let projectRoot: String
    private var ownersByRefPath: [String: Set<String>] = [:]
    private var ownersByAbsPath: [String: Set<String>] = [:]
    private var ownersByNormPath: [String: Set<String>] = [:]
    private var allFileRefs: Set<String> = []
    private var allAbsPaths: Set<String> = []
    private var allNormPaths: Set<String> = []

    init(project: XcodeProj, projectPath: String) {
        self.proj = project
        let projDirURL = URL(fileURLWithPath: projectPath).deletingLastPathComponent()
        self.projectRoot = projDirURL.standardizedFileURL.path
        buildIndex()
    }

    func owners(forPath path: String, mode: XcodeProjectQuery.PathMode) -> Set<String> {
        switch mode {
        case .fileRef: return ownersByRefPath[path] ?? []
        case .absolute: return ownersByAbsPath[path] ?? []
        case .normalized: return ownersByNormPath[path] ?? []
        }
    }

    func filesWithMultipleTargets(mode: XcodeProjectQuery.PathMode) -> [(key: String, value: Set<String>)] {
        let dict: [String: Set<String>] = {
            switch mode {
            case .fileRef: return ownersByRefPath
            case .absolute: return ownersByAbsPath
            case .normalized: return ownersByNormPath
            }
        }()
        return dict.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
    }

    func filesWithoutTargets(mode: XcodeProjectQuery.PathMode) -> [String] {
        let all: Set<String> = {
            switch mode {
            case .fileRef: return allFileRefs
            case .absolute: return allAbsPaths
            case .normalized: return allNormPaths
            }
        }()
        let withOwners: Set<String> = {
            switch mode {
            case .fileRef: return Set(ownersByRefPath.keys)
            case .absolute: return Set(ownersByAbsPath.keys)
            case .normalized: return Set(ownersByNormPath.keys)
            }
        }()
        return Array(all.subtracting(withOwners)).sorted()
    }

    private func buildIndex() {
        // Collect all file references of source-like files
        let refs = proj.pbxproj.fileReferences
        var sourceRefs: [PBXFileReference] = []
        for fr in refs {
            if let name = fr.path ?? fr.name, isSourceLike(name) {
                sourceRefs.append(fr)
                let (refPath, absPath, normPath) = paths(for: fr)
                if let refPath { allFileRefs.insert(refPath) }
                if let absPath { allAbsPaths.insert(absPath) }
                if let normPath { allNormPaths.insert(normPath) }
            }
        }

        // Map ownership via sources build phases
        for target in proj.pbxproj.nativeTargets {
            let targetName = target.name
            for phase in target.buildPhases.compactMap({ $0 as? PBXSourcesBuildPhase }) {
                for bf in phase.files ?? [] {
                    if let fr = bf.file as? PBXFileReference {
                        guard let name = fr.path ?? fr.name, isSourceLike(name) else { continue }
                        let (refPath, absPath, normPath) = paths(for: fr)
                        if let refPath { ownersByRefPath[refPath, default: []].insert(targetName) }
                        if let absPath { ownersByAbsPath[absPath, default: []].insert(targetName) }
                        if let normPath { ownersByNormPath[normPath, default: []].insert(targetName) }
                    }
                }
            }
        }
    }

    private func isSourceLike(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".swift") || lower.hasSuffix(".m") || lower.hasSuffix(".mm") || lower.hasSuffix(".c") || lower.hasSuffix(".cc") || lower.hasSuffix(".cpp")
    }

    private func paths(for fr: PBXFileReference) -> (String?, String?, String?) {
        let ref = fr.path ?? fr.name
        var refPath: String? = ref
        var absPath: String?
        var norm: String?
        if let fullStr = (try? fr.fullPath(sourceRoot: projectRoot)) ?? nil {
            let stdFull = URL(fileURLWithPath: fullStr).standardizedFileURL.path
            absPath = stdFull
            if stdFull.hasPrefix(projectRoot + "/") {
                norm = String(stdFull.dropFirst(projectRoot.count + 1))
            } else {
                norm = stdFull
            }
        } else if let r = ref {
            refPath = r
            let stdRel = URL(fileURLWithPath: r, relativeTo: URL(fileURLWithPath: projectRoot)).standardizedFileURL.path
            absPath = stdRel
            if stdRel.hasPrefix(projectRoot + "/") {
                norm = String(stdRel.dropFirst(projectRoot.count + 1))
            } else {
                norm = stdRel
            }
        }
        return (refPath, absPath, norm)
    }
}
