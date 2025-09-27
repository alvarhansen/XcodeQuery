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
struct GProjectBuildSetting { let configuration: String; let key: String; let value: String?; let values: [String]?; let isArray: Bool }
struct GTargetBuildSetting { let target: String; let configuration: String; let key: String; let value: String?; let values: [String]?; let isArray: Bool; let origin: String }
struct GBuildSetting { let configuration: String; let key: String; let value: String?; let values: [String]?; let isArray: Bool; let origin: String }

// Swift Packages wrappers
struct GPackageRequirement { let kind: String; let value: String }
struct GPackageProduct { let name: String; let type: String }
struct GPackageConsumer { let target: String; let product: String }
struct GSwiftPackage { let name: String; let identity: String; let url: String?; let requirement: GPackageRequirement; let products: [GPackageProduct]; let consumers: [GPackageConsumer] }
struct GPackageUsage { let target: String; let packageName: String; let productName: String }

// MARK: - Resolvers

enum XQResolvers {
    // MARK: Query root
    static func resolveBuildConfigurations(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let ctx = try expectCtx(context)
        var names = Set<String>()
        // Project-level configurations
        if let proj = ctx.project.pbxproj.projects.first, let list = proj.buildConfigurationList {
            for c in list.buildConfigurations { names.insert(c.name) }
        }
        // Target-level configurations
        for t in ctx.project.pbxproj.nativeTargets {
            if let list = t.buildConfigurationList {
                for c in list.buildConfigurations { names.insert(c.name) }
            }
        }
        return Array(names).sorted()
    }
    static func resolveProjectBuildSettings(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let ctx = try expectCtx(context)
        var rows: [GProjectBuildSetting] = []
        // Project-level configurations
        guard let proj = ctx.project.pbxproj.projects.first, let list = proj.buildConfigurationList else {
            return rows
        }
        for cfg in list.buildConfigurations {
            let cfgName = cfg.name
            let settings = cfg.buildSettings
            for (key, raw) in settings {
                let norm = normalizeSettingValue(raw)
                rows.append(GProjectBuildSetting(configuration: cfgName, key: key, value: norm.value, values: norm.values, isArray: norm.isArray))
            }
        }
        // Filter by configuration/key if provided
        if let filter = args["filter"].dictionary {
            rows = rows.filter { matchPBSFilter(configuration: $0.configuration, key: $0.key, filter: filter) }
        }
        // Sort: configuration, key
        rows.sort { a, b in
            if a.configuration != b.configuration { return a.configuration < b.configuration }
            return a.key < b.key
        }
        return rows
    }
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

    // MARK: Swift Packages — Root resolvers
    static func resolveSwiftPackages(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let ctx = try expectCtx(context)
        let index = try buildPackageIndex(ctx: ctx)
        var list = index.packages
        if let filter = args["filter"].dictionary {
            list = list.filter { p in
                var ok = true
                if let v = filter["name"], !v.isUndefined, !v.isNull { ok = ok && matchString(p.name, value: v) }
                if let v = filter["identity"], !v.isUndefined, !v.isNull { ok = ok && matchString(p.identity, value: v) }
                if let v = filter["url"], !v.isUndefined, !v.isNull { ok = ok && matchString(p.url ?? "", value: v) }
                if let v = filter["product"], !v.isUndefined, !v.isNull { ok = ok && p.products.contains { matchString($0.name, value: v) } }
                if let v = filter["consumerTarget"], !v.isUndefined, !v.isNull { ok = ok && p.consumers.contains { matchString($0.target, value: v) } }
                return ok
            }
        }
        list.sort { a, b in
            if a.identity != b.identity { return a.identity < b.identity }
            return a.name < b.name
        }
        return list
    }

    static func resolveTargetPackageProducts(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let ctx = try expectCtx(context)
        _ = try buildPackageIndex(ctx: ctx) // ensure indexable; currently unused but may validate
        var rows: [GPackageUsage] = []
        for nt in ctx.project.pbxproj.nativeTargets {
            rows.append(contentsOf: try packageUsagesForTarget(nt: nt, ctx: ctx))
        }
        if let filter = args["filter"].dictionary {
            rows = rows.filter { r in
                var ok = true
                if let v = filter["target"], !v.isUndefined, !v.isNull { ok = ok && matchString(r.target, value: v) }
                if let v = filter["package"], !v.isUndefined, !v.isNull { ok = ok && matchString(r.packageName, value: v) }
                if let v = filter["product"], !v.isUndefined, !v.isNull { ok = ok && matchString(r.productName, value: v) }
                return ok
            }
        }
        rows.sort { a, b in
            if a.target != b.target { return a.target < b.target }
            if a.packageName != b.packageName { return a.packageName < b.packageName }
            return a.productName < b.productName
        }
        return rows
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

    static func resolveTarget_packageProducts(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let t = try expect(source, as: GTarget.self)
        var rows = try packageUsagesForTarget(nt: t.nt, ctx: t.ctx)
        if let filter = args["filter"].dictionary {
            rows = rows.filter { r in
                if let nameV = filter["name"], !nameV.isUndefined, !nameV.isNull { return matchString(r.productName, value: nameV) }
                return true
            }
        }
        rows.sort { a, b in a.packageName == b.packageName ? a.productName < b.productName : a.packageName < b.packageName }
        return rows
    }

    static func resolveTarget_buildSettings(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let t = try expect(source, as: GTarget.self)
        enum Scope { case projectOnly, targetOnly, merged }
        func parseScope(_ m: Map?) -> Scope { switch m?.string?.uppercased() {
            case "PROJECT_ONLY": return .projectOnly
            case "MERGED": return .merged
            default: return .targetOnly
        } }
        let scope = parseScope(args["scope"]) // default handled in schema

        // Collect settings per configuration
        var projectSettingsByConfig: [String: [String: Any]] = [:]
        if let proj = t.ctx.project.pbxproj.projects.first, let list = proj.buildConfigurationList {
            for cfg in list.buildConfigurations { projectSettingsByConfig[cfg.name] = cfg.buildSettings }
        }
        var targetSettingsByConfig: [String: [String: Any]] = [:]
        if let list = t.nt.buildConfigurationList {
            for cfg in list.buildConfigurations { targetSettingsByConfig[cfg.name] = cfg.buildSettings }
        }

        var rows: [GBuildSetting] = []
        var names = Set<String>()
        switch scope {
        case .projectOnly: names.formUnion(projectSettingsByConfig.keys)
        case .targetOnly: names.formUnion(targetSettingsByConfig.keys)
        case .merged: names.formUnion(projectSettingsByConfig.keys); names.formUnion(targetSettingsByConfig.keys)
        }
        for cfgName in names {
            let proj = projectSettingsByConfig[cfgName] ?? [:]
            let tgt = targetSettingsByConfig[cfgName] ?? [:]
            switch scope {
            case .projectOnly:
                for (k, v) in proj { let n = normalizeSettingValue(v); rows.append(GBuildSetting(configuration: cfgName, key: k, value: n.value, values: n.values, isArray: n.isArray, origin: "PROJECT")) }
            case .targetOnly:
                for (k, v) in tgt { let n = normalizeSettingValue(v); rows.append(GBuildSetting(configuration: cfgName, key: k, value: n.value, values: n.values, isArray: n.isArray, origin: "TARGET")) }
            case .merged:
                var merged = proj
                var origin: [String: String] = Dictionary(uniqueKeysWithValues: proj.keys.map { ($0, "PROJECT") })
                for (k, v) in tgt { merged[k] = v; origin[k] = "TARGET" }
                for (k, v) in merged { let n = normalizeSettingValue(v); rows.append(GBuildSetting(configuration: cfgName, key: k, value: n.value, values: n.values, isArray: n.isArray, origin: origin[k] ?? "PROJECT")) }
            }
        }
        // Filter by configuration/key if provided
        if let filter = args["filter"].dictionary {
            rows = rows.filter { r in
                var ok = true
                if let cfg = filter["configuration"], !cfg.isUndefined, !cfg.isNull { ok = ok && matchString(r.configuration, value: cfg) }
                if let k = filter["key"], !k.isUndefined, !k.isNull { ok = ok && matchString(r.key, value: k) }
                return ok
            }
        }
        rows.sort { a, b in if a.configuration != b.configuration { return a.configuration < b.configuration } else { return a.key < b.key } }
        return rows
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

    // MARK: ProjectBuildSetting leaf resolvers
    static func resolveProjectBuildSetting_configuration(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GProjectBuildSetting.self).configuration }
    static func resolveProjectBuildSetting_key(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GProjectBuildSetting.self).key }
    static func resolveProjectBuildSetting_value(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GProjectBuildSetting.self).value }
    static func resolveProjectBuildSetting_values(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GProjectBuildSetting.self).values }
    static func resolveProjectBuildSetting_isArray(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GProjectBuildSetting.self).isArray }

    // MARK: TargetBuildSetting leaf resolvers
    static func resolveTargetBuildSetting_target(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GTargetBuildSetting.self).target }
    static func resolveTargetBuildSetting_configuration(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GTargetBuildSetting.self).configuration }
    static func resolveTargetBuildSetting_key(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GTargetBuildSetting.self).key }
    static func resolveTargetBuildSetting_value(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GTargetBuildSetting.self).value }
    static func resolveTargetBuildSetting_values(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GTargetBuildSetting.self).values }
    static func resolveTargetBuildSetting_isArray(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GTargetBuildSetting.self).isArray }
    static func resolveTargetBuildSetting_origin(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GTargetBuildSetting.self).origin }

    // MARK: BuildSetting (nested under Target) leaf resolvers
    static func resolveBuildSetting_configuration(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GBuildSetting.self).configuration }
    static func resolveBuildSetting_key(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GBuildSetting.self).key }
    static func resolveBuildSetting_value(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GBuildSetting.self).value }
    static func resolveBuildSetting_values(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GBuildSetting.self).values }
    static func resolveBuildSetting_isArray(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GBuildSetting.self).isArray }
    static func resolveBuildSetting_origin(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GBuildSetting.self).origin }

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

    // MARK: Build settings helpers
    private static func normalizeSettingValue(_ any: Any) -> (value: String?, values: [String]?, isArray: Bool) {
        if let arr = any as? [String] {
            return (nil, arr.map { String($0) }, true)
        }
        if let arrAny = any as? [Any] {
            let strs = arrAny.map { String(describing: $0) }
            return (nil, strs, true)
        }
        return (String(describing: any), nil, false)
    }

    private static func matchPBSFilter(configuration: String, key: String, filter: OrderedDictionary<String, Map>) -> Bool {
        var ok = true
        if let cfg = filter["configuration"], !cfg.isUndefined, !cfg.isNull { ok = ok && matchString(configuration, value: cfg) }
        if let k = filter["key"], !k.isUndefined, !k.isNull { ok = ok && matchString(key, value: k) }
        return ok
    }

    private static func matchTBSFilter(target: String, configuration: String, key: String, filter: OrderedDictionary<String, Map>) -> Bool {
        var ok = true
        if let tgt = filter["target"], !tgt.isUndefined, !tgt.isNull { ok = ok && matchString(target, value: tgt) }
        if let cfg = filter["configuration"], !cfg.isUndefined, !cfg.isNull { ok = ok && matchString(configuration, value: cfg) }
        if let k = filter["key"], !k.isUndefined, !k.isNull { ok = ok && matchString(key, value: k) }
        return ok
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

    static func resolveTargetBuildSettings(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? {
        let ctx = try expectCtx(context)
        enum Scope { case projectOnly, targetOnly, merged }
        func parseScope(_ m: Map?) -> Scope { switch m?.string?.uppercased() {
            case "PROJECT_ONLY": return .projectOnly
            case "MERGED": return .merged
            default: return .targetOnly
        } }
        let scope = parseScope(args["scope"]) // default handled in schema

        // Collect project-level config map
        var projectSettingsByConfig: [String: [String: Any]] = [:]
        if let proj = ctx.project.pbxproj.projects.first, let list = proj.buildConfigurationList {
            for cfg in list.buildConfigurations { projectSettingsByConfig[cfg.name] = cfg.buildSettings }
        }

        var rows: [GTargetBuildSetting] = []
        for nt in ctx.project.pbxproj.nativeTargets {
            // Collect target-level settings per config
            var targetSettingsByConfig: [String: [String: Any]] = [:]
            if let list = nt.buildConfigurationList {
                for cfg in list.buildConfigurations { targetSettingsByConfig[cfg.name] = cfg.buildSettings }
            }
            // Determine candidate configuration names
            var names = Set<String>()
            switch scope {
            case .projectOnly:
                names.formUnion(projectSettingsByConfig.keys)
            case .targetOnly:
                names.formUnion(targetSettingsByConfig.keys)
            case .merged:
                names.formUnion(projectSettingsByConfig.keys)
                names.formUnion(targetSettingsByConfig.keys)
            }
            for cfgName in names {
                let proj = projectSettingsByConfig[cfgName] ?? [:]
                let tgt = targetSettingsByConfig[cfgName] ?? [:]
                switch scope {
                case .projectOnly:
                    for (k, v) in proj {
                        let norm = normalizeSettingValue(v)
                        rows.append(GTargetBuildSetting(target: nt.name, configuration: cfgName, key: k, value: norm.value, values: norm.values, isArray: norm.isArray, origin: "PROJECT"))
                    }
                case .targetOnly:
                    for (k, v) in tgt {
                        let norm = normalizeSettingValue(v)
                        rows.append(GTargetBuildSetting(target: nt.name, configuration: cfgName, key: k, value: norm.value, values: norm.values, isArray: norm.isArray, origin: "TARGET"))
                    }
                case .merged:
                    var merged = proj
                    var origin: [String: String] = Dictionary(uniqueKeysWithValues: proj.keys.map { ($0, "PROJECT") })
                    for (k, v) in tgt { merged[k] = v; origin[k] = "TARGET" }
                    for (k, v) in merged {
                        let norm = normalizeSettingValue(v)
                        rows.append(GTargetBuildSetting(target: nt.name, configuration: cfgName, key: k, value: norm.value, values: norm.values, isArray: norm.isArray, origin: origin[k] ?? "PROJECT"))
                    }
                }
            }
        }
        // Filter
        if let filter = args["filter"].dictionary {
            rows = rows.filter { matchTBSFilter(target: $0.target, configuration: $0.configuration, key: $0.key, filter: filter) }
        }
        // Sort: target, configuration, key
        rows.sort { a, b in
            if a.target != b.target { return a.target < b.target }
            if a.configuration != b.configuration { return a.configuration < b.configuration }
            return a.key < b.key
        }
        return rows
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

// MARK: - Swift Packages helpers
private struct PackageIndex { var packages: [GSwiftPackage] }

private func buildPackageIndex(ctx: XQGQLContext) throws -> PackageIndex {
    var packageInfos: [String: (name: String, identity: String, url: String?, requirement: GPackageRequirement)] = [:]
    var productsByPackage: [String: [String: String]] = [:] // packageName -> productName -> type
    var consumers: [String: [String: Set<String>]] = [:] // packageName -> productName -> Set(target)

    if let proj = ctx.project.pbxproj.projects.first {
        for p in proj.remotePackages {
            let name = p.name ?? (p.repositoryURL?.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: ".git", with: "") ?? "")
            let identity = name.lowercased()
            let req = toRequirement(p.versionRequirement)
            packageInfos[name] = (name: name, identity: identity, url: p.repositoryURL, requirement: req)
        }
        for lp in proj.localPackages {
            let name = lp.name ?? lp.relativePath
            let identity = name.lowercased()
            let req = GPackageRequirement(kind: "EXACT", value: "")
            if packageInfos[name] == nil {
                packageInfos[name] = (name: name, identity: identity, url: nil, requirement: req)
            }
        }
    }

    for t in ctx.project.pbxproj.nativeTargets {
        if let deps = t.packageProductDependencies {
            for d in deps {
                let pkgName = d.package?.name ?? inferLocalPackageName(for: d)
                guard !pkgName.isEmpty else { continue }
                let prod = d.productName
                let type = "LIBRARY"
                productsByPackage[pkgName, default: [:]][prod] = type
                var byProd = consumers[pkgName, default: [:]]
                var set = byProd[prod, default: Set<String>()]
                set.insert(t.name)
                byProd[prod] = set
                consumers[pkgName] = byProd
            }
        }
    }

    var packages: [GSwiftPackage] = []
    for (name, meta) in packageInfos {
        let prods = productsByPackage[name]?.map { GPackageProduct(name: $0.key, type: $0.value) } ?? []
        var cons: [GPackageConsumer] = []
        if let pc = consumers[name] {
            for (product, targets) in pc {
                for t in targets { cons.append(GPackageConsumer(target: t, product: product)) }
            }
        }
        let pkg = GSwiftPackage(name: meta.name, identity: meta.identity, url: meta.url, requirement: meta.requirement, products: prods.sorted { $0.name < $1.name }, consumers: cons.sorted { a, b in a.target == b.target ? a.product < b.product : a.target < b.target })
        packages.append(pkg)
    }
    return PackageIndex(packages: packages)
}

private func inferLocalPackageName(for dep: XCSwiftPackageProductDependency) -> String {
    // XcodeProj doesn't link local package refs to the product dependency; fall back to product name.
    return dep.productName
}

private func toRequirement(_ vr: XCRemoteSwiftPackageReference.VersionRequirement?) -> GPackageRequirement {
    guard let vr else { return GPackageRequirement(kind: "EXACT", value: "") }
    switch vr {
    case .exact(let v): return GPackageRequirement(kind: "EXACT", value: v)
    case .upToNextMajorVersion(let v): return GPackageRequirement(kind: "UP_TO_NEXT_MAJOR", value: v)
    case .upToNextMinorVersion(let v): return GPackageRequirement(kind: "UP_TO_NEXT_MINOR", value: v)
    case .range(let from, let to): return GPackageRequirement(kind: "RANGE", value: "\(from)...\(to)")
    case .branch(let b): return GPackageRequirement(kind: "BRANCH", value: b)
    case .revision(let r): return GPackageRequirement(kind: "REVISION", value: r)
    }
}

private func packageUsagesForTarget(nt: PBXNativeTarget, ctx: XQGQLContext) throws -> [GPackageUsage] {
    var rows: [GPackageUsage] = []
    if let deps = nt.packageProductDependencies {
        for d in deps {
            let pkgName = d.package?.name ?? inferLocalPackageName(for: d)
            guard !pkgName.isEmpty else { continue }
            rows.append(GPackageUsage(target: nt.name, packageName: pkgName, productName: d.productName))
        }
    }
    return rows
}

// MARK: Swift Packages leaf resolvers
extension XQResolvers {
    static func resolveSwiftPackage_name(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GSwiftPackage.self).name }
    static func resolveSwiftPackage_identity(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GSwiftPackage.self).identity }
    static func resolveSwiftPackage_url(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GSwiftPackage.self).url }
    static func resolveSwiftPackage_requirement(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GSwiftPackage.self).requirement }
    static func resolveSwiftPackage_products(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GSwiftPackage.self).products }
    static func resolveSwiftPackage_consumers(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GSwiftPackage.self).consumers }

    static func resolvePackageRequirement_kind(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GPackageRequirement.self).kind }
    static func resolvePackageRequirement_value(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GPackageRequirement.self).value }

    static func resolvePackageProduct_name(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GPackageProduct.self).name }
    static func resolvePackageProduct_type(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GPackageProduct.self).type }

    static func resolvePackageConsumer_target(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GPackageConsumer.self).target }
    static func resolvePackageConsumer_product(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GPackageConsumer.self).product }

    static func resolvePackageUsage_target(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GPackageUsage.self).target }
    static func resolvePackageUsage_packageName(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GPackageUsage.self).packageName }
    static func resolvePackageUsage_productName(_ source: Any, _ args: Map, _ context: Any, _ info: GraphQLResolveInfo) throws -> Any? { try expect(source, as: GPackageUsage.self).productName }
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
