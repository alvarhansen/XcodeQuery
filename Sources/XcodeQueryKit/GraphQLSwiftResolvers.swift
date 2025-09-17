import Foundation
import GraphQL
import OrderedCollections
import XcodeProj

// Adapter layer: GraphQLSwift resolvers backed by XcodeProj and logic mirroring GraphQLExecutor behavior.

struct XQGQLContext {
    let project: XcodeProj
    let projectPath: String
}

// MARK: - Wrapper objects used as GraphQL sources

struct GTarget { let nt: PBXNativeTarget; let ctx: XQGQLContext }
struct GSource { let path: String }
struct GResource { let path: String }
struct GBuildScript { let bs: BuildScriptEntry }
struct GFlatSource { let target: String; let path: String }
struct GFlatResource { let target: String; let path: String }
struct GFlatDependency { let target: String; let dep: PBXNativeTarget }
struct GFlatBuildScript { let target: String; let bs: BuildScriptEntry }
struct GMembership { let path: String; let targets: [String] }

// MARK: - Resolvers

enum XQResolvers {
    // MARK: Query root
    static func resolveTargets(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let ctx = try expectCtx(context)
        var list = ctx.project.pbxproj.nativeTargets
        if let typeSym = args["type"].string, let tt = TargetType.from(enumSymbol: typeSym) {
            list = list.filter { TargetType.from(productType: $0.productType) == tt }
        }
        if let filter = args["filter"].dictionary {
            list = list.filter { matchTargetFilter(nt: $0, filter: filter) }
        }
        list.sort { $0.name < $1.name }
        return list.map { GTarget(nt: $0, ctx: ctx) }
    }

    static func resolveTarget(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let ctx = try expectCtx(context)
        guard let name = args["name"].string else { throw GraphQLError(message: "target(name: String!) is required") }
        guard let nt = ctx.project.pbxproj.nativeTargets.first(where: { $0.name == name }) else {
            throw GraphQLError(message: "Unknown target: \(name)")
        }
        return GTarget(nt: nt, ctx: ctx)
    }

    static func resolveDependenciesTop(reverse: Bool) -> GraphQLFieldResolveInput {
        return { _, args, context, _ in
            let ctx = try expectCtx(context)
            guard let name = args["name"].string else { throw GraphQLError(message: "name: String! required") }
            let recursive = args["recursive"].bool ?? false
            let graph = DependencyGraph(project: ctx.project)
            let deps = try graph.resolve(base: name, reverse: reverse, recursive: recursive)
            var list = deps
            if let filter = args["filter"].dictionary {
                list = list.filter { matchTargetFilter(nt: $0, filter: filter) }
            }
            return list.map { GTarget(nt: $0, ctx: ctx) }
        }
    }

    static func resolveTargetSources(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let ctx = try expectCtx(context)
        let mode = parsePathMode(args["pathMode"]) ?? .fileRef
        var rows: [GFlatSource] = []
        for t in ctx.project.pbxproj.nativeTargets {
            let paths = try sourceFiles(targetName: t.name, mode: mode, ctx: ctx)
            for p in paths { rows.append(GFlatSource(target: t.name, path: p)) }
        }
        if let filter = args["filter"].dictionary {
            rows = rows.filter { row in
                var ok = true
                if let pathVal = filter["path"], !pathVal.isUndefined, !pathVal.isNull {
                    ok = ok && matchString(row.path, key: "path", obj: filter)
                }
                if let targetVal = filter["target"], !targetVal.isUndefined, !targetVal.isNull {
                    ok = ok && matchString(row.target, key: "target", obj: filter)
                }
                return ok
            }
        }
        rows.sort { $0.target == $1.target ? $0.path < $1.path : $0.target < $1.target }
        return rows
    }

    static func resolveTargetResources(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let ctx = try expectCtx(context)
        let mode = parsePathMode(args["pathMode"]) ?? .fileRef
        var rows: [GFlatResource] = []
        for t in ctx.project.pbxproj.nativeTargets {
            let paths = try resourceFiles(targetName: t.name, mode: mode, ctx: ctx)
            for p in paths { rows.append(GFlatResource(target: t.name, path: p)) }
        }
        if let filter = args["filter"].dictionary {
            rows = rows.filter { row in
                var ok = true
                if let pathVal = filter["path"], !pathVal.isUndefined, !pathVal.isNull {
                    ok = ok && matchString(row.path, key: "path", obj: filter)
                }
                if let targetVal = filter["target"], !targetVal.isUndefined, !targetVal.isNull {
                    ok = ok && matchString(row.target, key: "target", obj: filter)
                }
                return ok
            }
        }
        rows.sort { $0.target == $1.target ? $0.path < $1.path : $0.target < $1.target }
        return rows
    }

    static func resolveTargetDependencies(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let ctx = try expectCtx(context)
        let recursive = args["recursive"].bool ?? false
        let graph = DependencyGraph(project: ctx.project)
        var rows: [GFlatDependency] = []
        for t in ctx.project.pbxproj.nativeTargets {
            let deps = try graph.resolve(base: t.name, reverse: false, recursive: recursive)
            for d in deps { rows.append(GFlatDependency(target: t.name, dep: d)) }
        }
        if let filter = args["filter"].dictionary {
            rows = rows.filter { matchTargetFilter(nt: $0.dep, filter: filter) }
        }
        rows.sort {
            if $0.target != $1.target { return $0.target < $1.target }
            if $0.dep.name != $1.dep.name { return $0.dep.name < $1.dep.name }
            return TargetType.from(productType: $0.dep.productType).gqlEnum < TargetType.from(productType: $1.dep.productType).gqlEnum
        }
        return rows
    }

    static func resolveTargetBuildScripts(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let ctx = try expectCtx(context)
        var rows: [GFlatBuildScript] = []
        for t in ctx.project.pbxproj.nativeTargets {
            for s in try buildScripts(targetName: t.name, ctx: ctx) { rows.append(GFlatBuildScript(target: t.name, bs: s)) }
        }
        if let filter = args["filter"].dictionary {
            rows = rows.filter { matchBuildScript($0.bs, obj: filter) }
        }
        rows.sort { a, b in
            if a.target != b.target { return a.target < b.target }
            let asg = a.bs.stage == .pre ? 0 : 1
            let bsg = b.bs.stage == .pre ? 0 : 1
            if asg != bsg { return asg < bsg }
            return (a.bs.name ?? "") < (b.bs.name ?? "")
        }
        return rows
    }

    static func resolveTargetMembership(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let ctx = try expectCtx(context)
        guard let path = args["path"].string else { throw GraphQLError(message: "path: String! required") }
        let mode = parsePathMode(args["pathMode"]) ?? .fileRef
        var owners = Set<String>()
        for t in ctx.project.pbxproj.nativeTargets {
            let list = try sourceFiles(targetName: t.name, mode: mode, ctx: ctx)
            if list.contains(path) { owners.insert(t.name) }
        }
        return GMembership(path: path, targets: Array(owners).sorted())
    }

    // MARK: Target object
    static func resolveTarget_name(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let t = try expect(source, as: GTarget.self)
        return t.nt.name
    }
    static func resolveTarget_type(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let t = try expect(source, as: GTarget.self)
        return TargetType.from(productType: t.nt.productType).gqlEnum
    }
    static func resolveTarget_dependencies(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let t = try expect(source, as: GTarget.self)
        let recursive = args["recursive"].bool ?? false
        let graph = DependencyGraph(project: t.ctx.project)
        var deps = try graph.resolve(base: t.nt.name, reverse: false, recursive: recursive)
        if let filter = args["filter"].dictionary {
            deps = deps.filter { matchTargetFilter(nt: $0, filter: filter) }
        }
        return deps.map { GTarget(nt: $0, ctx: t.ctx) }
    }
    static func resolveTarget_sources(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let t = try expect(source, as: GTarget.self)
        let mode = parsePathMode(args["pathMode"]) ?? .fileRef
        var paths = try sourceFiles(targetName: t.nt.name, mode: mode, ctx: t.ctx)
        if let filter = args["filter"].dictionary {
            if let pathVal = filter["path"], !pathVal.isUndefined, !pathVal.isNull {
                paths = paths.filter { matchString($0, key: "path", obj: filter) }
            }
        }
        return paths.map(GSource.init(path:))
    }
    static func resolveTarget_resources(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let t = try expect(source, as: GTarget.self)
        let mode = parsePathMode(args["pathMode"]) ?? .fileRef
        var paths = try resourceFiles(targetName: t.nt.name, mode: mode, ctx: t.ctx)
        if let filter = args["filter"].dictionary {
            if let pathVal = filter["path"], !pathVal.isUndefined, !pathVal.isNull {
                paths = paths.filter { matchString($0, key: "path", obj: filter) }
            }
        }
        return paths.map(GResource.init(path:))
    }
    static func resolveTarget_buildScripts(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let t = try expect(source, as: GTarget.self)
        var bs = try buildScripts(targetName: t.nt.name, ctx: t.ctx)
        if let filter = args["filter"].dictionary { bs = bs.filter { matchBuildScript($0, obj: filter) } }
        let wrapped = bs.map(GBuildScript.init(bs:))
        #if DEBUG
        fputs("[xcq-debug] resolveTarget_buildScripts: target=\(t.nt.name), count=\(wrapped.count)\n", stderr)
        #endif
        return wrapped
    }

    // MARK: Leaf object resolvers
    static func resolveSource_path(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GSource.self).path }
    static func resolveResource_path(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GResource.self).path }
    static func resolveBuildScript_name(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GBuildScript.self).bs.name }
    static func resolveBuildScript_stage(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let bs = try expect(source, as: GBuildScript.self).bs
        #if DEBUG
        fputs("[xcq-debug] resolveBuildScript_stage: target=\(bs.target), name=\(bs.name ?? "<nil>") stage=\(bs.stage == .pre ? "PRE" : "POST")\n", stderr)
        #endif
        return (bs.stage == .pre ? "PRE" : "POST")
    }
    static func resolveBuildScript_inputPaths(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GBuildScript.self).bs.inputPaths }
    static func resolveBuildScript_outputPaths(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GBuildScript.self).bs.outputPaths }
    static func resolveBuildScript_inputFileListPaths(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GBuildScript.self).bs.inputFileListPaths }
    static func resolveBuildScript_outputFileListPaths(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GBuildScript.self).bs.outputFileListPaths }

    static func resolveFlatSource_target(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GFlatSource.self).target }
    static func resolveFlatSource_path(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GFlatSource.self).path }
    static func resolveFlatResource_target(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GFlatResource.self).target }
    static func resolveFlatResource_path(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GFlatResource.self).path }
    static func resolveFlatDependency_target(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GFlatDependency.self).target }
    static func resolveFlatDependency_name(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GFlatDependency.self).dep.name }
    static func resolveFlatDependency_type(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let d = try expect(source, as: GFlatDependency.self).dep
        return TargetType.from(productType: d.productType).gqlEnum
    }
    static func resolveFlatBuildScript_target(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GFlatBuildScript.self).target }
    static func resolveFlatBuildScript_name(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GFlatBuildScript.self).bs.name }
    static func resolveFlatBuildScript_stage(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let bs = try expect(source, as: GFlatBuildScript.self).bs
        return (bs.stage == .pre ? "PRE" : "POST")
    }
    static func resolveFlatBuildScript_inputPaths(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GFlatBuildScript.self).bs.inputPaths }
    static func resolveFlatBuildScript_outputPaths(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GFlatBuildScript.self).bs.outputPaths }
    static func resolveFlatBuildScript_inputFileListPaths(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GFlatBuildScript.self).bs.inputFileListPaths }
    static func resolveFlatBuildScript_outputFileListPaths(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GFlatBuildScript.self).bs.outputFileListPaths }
    static func resolveMembership_path(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GMembership.self).path }
    static func resolveMembership_targets(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GMembership.self).targets }

    // MARK: Helpers: context, casting
    private static func expectCtx(_ any: Any) throws -> XQGQLContext {
        guard let ctx = any as? XQGQLContext else { throw GraphQLError(message: "Missing execution context") }
        return ctx
    }
    private static func expect<T>(_ any: Any, as: T.Type) throws -> T {
        guard let v = any as? T else { throw GraphQLError(message: "Invalid source type for resolver") }
        return v
    }

    // MARK: Data helpers (ported from GraphQLExecutor)
    private enum PathMode { case fileRef, absolute, normalized }
    private static func parsePathMode(_ m: Map?) -> PathMode? {
        guard let s = m?.string?.uppercased() else { return nil }
        switch s { case "FILE_REF": return .fileRef; case "ABSOLUTE": return .absolute; case "NORMALIZED": return .normalized; default: return nil }
    }

    private static func sourceFiles(targetName: String, mode: PathMode, ctx: XQGQLContext) throws -> [String] {
        guard let nt = ctx.project.pbxproj.nativeTargets.first(where: { $0.name == targetName }) else { throw GraphQLError(message: "Unknown target: \(targetName)") }
        let projDirURL = URL(fileURLWithPath: ctx.projectPath).deletingLastPathComponent()
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

    private static func resourceFiles(targetName: String, mode: PathMode, ctx: XQGQLContext) throws -> [String] {
        guard let nt = ctx.project.pbxproj.nativeTargets.first(where: { $0.name == targetName }) else { throw GraphQLError(message: "Unknown target: \(targetName)") }
        let projDirURL = URL(fileURLWithPath: ctx.projectPath).deletingLastPathComponent()
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

    private static func buildScripts(targetName: String, ctx: XQGQLContext) throws -> [BuildScriptEntry] {
        guard let nt = ctx.project.pbxproj.nativeTargets.first(where: { $0.name == targetName }) else { throw GraphQLError(message: "Unknown target: \(targetName)") }
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

    private static func matchTargetFilter(nt: PBXNativeTarget, filter: OrderedDictionary<String, Map>) -> Bool {
        let tname = nt.name
        let ttype = TargetType.from(productType: nt.productType)
        for (k, v) in filter {
            if v.isUndefined || v.isNull { continue }
            switch k {
            case "name": if !matchString(tname, value: v) { return false }
            case "type": if let sym = v.string, let tt = TargetType.from(enumSymbol: sym) { if tt != ttype { return false } } else { return false }
            default: return false
            }
        }
        return true
    }

    private static func matchBuildScript(_ s: BuildScriptEntry, obj: OrderedDictionary<String, Map>) -> Bool {
        for (k, v) in obj {
            if v.isUndefined || v.isNull { continue }
            switch k {
            case "stage": if let sym = v.string { if (s.stage == .pre ? "PRE" : "POST") != sym { return false } } else { return false }
            case "name": if !matchString(s.name ?? "", value: v) { return false }
            case "target": if !matchString(s.target, value: v) { return false }
            default: return false
            }
        }
        return true
    }

    private static func matchString(_ s: String, key: String = "", obj: OrderedDictionary<String, Map>) -> Bool {
        if let nested = obj[key] { return matchString(s, value: nested) }
        return matchString(s, value: .dictionary(obj))
    }
    private static func matchString(_ s: String, value: Map) -> Bool {
        guard case let .dictionary(o) = value else { return false }
        for (k, v) in o {
            // Skip undefined/null entries injected by GraphQLSwift for absent input fields
            if v.isUndefined || v.isNull { continue }
            switch k {
            case "eq": if let val = v.string { if s != val { return false } } else { return false }
            case "regex":
                if let pat = v.string { if (try? NSRegularExpression(pattern: pat)).map({ re in re.firstMatch(in: s, range: NSRange(location: 0, length: s.utf16.count)) != nil }) != true { return false } } else { return false }
            case "prefix": if let val = v.string { if !s.hasPrefix(val) { return false } } else { return false }
            case "suffix": if let val = v.string { if !s.hasSuffix(val) { return false } } else { return false }
            case "contains":
                if let val = v.string { if !s.contains(val) { return false } } else { return false }
            default: return false
            }
        }
        return true
    }
}

// MARK: - Dependency graph (ported)
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
            for d in deps { reverse[d.name, default: []].append(t) }
        }
        self.depsByName = forward
        self.revByName = reverse
    }

    func resolve(base: String, reverse: Bool, recursive: Bool) throws -> [PBXNativeTarget] {
        guard byName[base] != nil else { throw GraphQLError(message: "Unknown target: \(base)") }
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

// MARK: - Enum mapping (duplicate minimal mapping for adapters)
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
