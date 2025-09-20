import XCTest
import GraphQL
import NIO
import XcodeProj
import PathKit
import ProjectSpec
import XcodeGenKit
@testable import XcodeQueryKit

final class GraphQLSwiftResolverTests: XCTestCase {
    func testTargetsAndSourcesViaGraphQLSwift() throws {
        // Arrange project via baseline fixture
        let fixture = try GraphQLBaselineFixture()

        // Obtain schema and run query
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        // Extract context from fixture by reflection
        // NOTE: GraphQLBaselineFixture holds an XcodeProjectQuery; we re-create context by looking up its project path
        let mirror = Mirror(reflecting: fixture)
        guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
            XCTFail("Could not access projectQuery from fixture"); return
        }

        // We need XcodeProj to build context; re-open via known API
        let ctx: XQGQLContext = try {
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"])
            }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // Query 1: targets { name type }
        do {
            let result = try graphql(schema: schema, request: "{ targets { name type } }", context: ctx, eventLoopGroup: group).wait()
            guard let data = result.data?.dictionary, let arr = data["targets"]?.array else { XCTFail("No data"); return }
            let names = Set(arr.compactMap { $0.dictionary?["name"]?.string })
            XCTAssertEqual(names, ["App", "AppTests", "Lib"])
        }

        // Query 2: targetSources normalized
        do {
            let result = try graphql(schema: schema, request: "{ targetSources(pathMode: NORMALIZED) { target path } }", context: ctx, eventLoopGroup: group).wait()
            guard let data = result.data?.dictionary, let arr = data["targetSources"]?.array else { XCTFail("No data"); return }
            let found = arr.contains { row in
                if let d = row.dictionary, let t = d["target"]?.string, let p = d["path"]?.string {
                    return t == "Lib" && p.contains("Lib/Sources/LibFile.swift")
                }
                return false
            }
            XCTAssertTrue(found)
        }

        // Query 3: nested dependencies
        do {
            let q = "{ targets(type: UNIT_TEST) { name dependencies(recursive: true) { name } } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let data = result.data?.dictionary, let arr = data["targets"]?.array else { XCTFail("No data"); return }
            var deps = Set<String>()
            for tval in arr {
                if let d = tval.dictionary, let ds = d["dependencies"]?.array {
                    for dep in ds { if let name = dep.dictionary?["name"]?.string { deps.insert(name) } }
                }
            }
            XCTAssertEqual(deps, ["App", "Lib"])
        }
    }

    func testNestedSourcesFilterContainsDot() throws {
        // Arrange project via baseline fixture
        let fixture = try GraphQLBaselineFixture()

        // Obtain schema and run query
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        // Build context from fixture
        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not access projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // Query: nested sources with contains "." should match files with extensions
        let query = "{ targets { sources(filter: { path: { contains: \".\" } }) { path } } }"
        let result = try graphql(schema: schema, request: query, context: ctx, eventLoopGroup: group).wait()
        guard let data = result.data?.dictionary, let arr = data["targets"]?.array else { XCTFail("No data"); return }
        // Ensure at least one target reports at least one source
        let nonEmpty = arr.contains { tval in
            if let d = tval.dictionary, let srcs = d["sources"]?.array { return !srcs.isEmpty }
            return false
        }
        XCTAssertTrue(nonEmpty, "Expected some sources when filtering by contains '.'")
    }

    func testTargetsBuildScriptsPresence() throws {
        // Arrange project via baseline fixture
        let fixture = try GraphQLBaselineFixture()

        // Obtain schema and context
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Could not access projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // Query buildScripts nested under targets
        let q = "{ targets { name buildScripts { name stage } } }"
        let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
        if result.data == nil { XCTFail("No data: \(result.errors)"); return }
        guard let data = result.data?.dictionary, let tarr = data["targets"]?.array else { XCTFail("No data"); return }

        var counts: [String: Int] = [:]
        for tval in tarr {
            guard let name = tval.dictionary?["name"]?.string else { continue }
            let scripts = tval.dictionary?["buildScripts"]?.array ?? []
            counts[name] = scripts.count
        }

        // In our fixture: App has scripts, Lib and AppTests do not
        XCTAssertEqual(counts["Lib"], 0)
        XCTAssertEqual(counts["AppTests"], 0)
        XCTAssertNotNil(counts["App"])
        XCTAssertTrue((counts["App"] ?? 0) > 0)
    }

    func testFlatResourcesFilterContainsDot() throws {
        // Arrange project via baseline fixture
        let fixture = try GraphQLBaselineFixture()

        // Obtain schema and context
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Could not access projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // Top-level targetResources with contains "." should match resource file(s)
        let q = "{ targetResources(filter: { path: { contains: \".\" } }) { path } }"
        let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
        guard let data = result.data?.dictionary, let arr = data["targetResources"]?.array else { XCTFail("No data"); return }
        XCTAssertFalse(arr.isEmpty, "Expected some targetResources when filtering by contains '.'")
    }

    func testNestedResourcesFilterContainsDot() throws {
        // Arrange project via baseline fixture
        let fixture = try GraphQLBaselineFixture()

        // Obtain schema and context
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Could not access projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // Nested resources with contains '.' should return entries for at least one target
        let q = "{ targets { resources(filter: { path: { contains: \".\" } }) { path } } }"
        let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
        guard let data = result.data?.dictionary, let tarr = data["targets"]?.array else { XCTFail("No data"); return }
        let nonEmpty = tarr.contains { tval in
            if let d = tval.dictionary, let res = d["resources"]?.array { return !res.isEmpty }
            return false
        }
        XCTAssertTrue(nonEmpty, "Expected nested resources when filtering by contains '.'")
    }

    func testFlatSourcesFilterContainsDot() throws {
        // Arrange project via baseline fixture
        let fixture = try GraphQLBaselineFixture()

        // Obtain schema and context
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Could not access projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // Top-level targetSources with contains '.' should return some entries
        let q = "{ targetSources(filter: { path: { contains: \".\" } }) { path } }"
        let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
        guard let data = result.data?.dictionary, let arr = data["targetSources"]?.array else { XCTFail("No data"); return }
        XCTAssertFalse(arr.isEmpty, "Expected some targetSources when filtering by contains '.'")
    }

    func testAbsolutePathsForFlatSourcesAndResources() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let (ctx, projectRoot): (XQGQLContext, String) = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 50, userInfo: [NSLocalizedDescriptionKey: "Could not access projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            let root = URL(fileURLWithPath: projectPath).deletingLastPathComponent().standardizedFileURL.path
            return (XQGQLContext(project: proj, projectPath: projectPath), root)
        }()

        let q = "{ targetSources(pathMode: ABSOLUTE) { path } targetResources(pathMode: ABSOLUTE) { path } }"
        let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
        guard let data = result.data?.dictionary else { XCTFail("No data"); return }
        if let arr = data["targetSources"]?.array {
            XCTAssertFalse(arr.isEmpty)
            for v in arr { if let p = v.dictionary?["path"]?.string { XCTAssertTrue(p.hasPrefix(projectRoot + "/"), "Expected absolute source path under project root") } }
        } else { XCTFail("Missing targetSources") }
        if let arr = data["targetResources"]?.array {
            XCTAssertFalse(arr.isEmpty)
            for v in arr { if let p = v.dictionary?["path"]?.string { XCTAssertTrue(p.hasPrefix(projectRoot + "/"), "Expected absolute resource path under project root") } }
        } else { XCTFail("Missing targetResources") }
    }

    func testAbsolutePathsForNestedSourcesAndResources() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }

        let (ctx, projectRoot): (XQGQLContext, String) = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 60, userInfo: [NSLocalizedDescriptionKey: "Could not access projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 61, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            let root = URL(fileURLWithPath: projectPath).deletingLastPathComponent().standardizedFileURL.path
            return (XQGQLContext(project: proj, projectPath: projectPath), root)
        }()

        let q = "{ targets { name sources(pathMode: ABSOLUTE) { path } resources(pathMode: ABSOLUTE) { path } } }"
        let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
        guard let data = result.data?.dictionary, let tarr = data["targets"]?.array else { XCTFail("No data"); return }
        var sawSource = false
        var sawResource = false
        for tval in tarr {
            if let d = tval.dictionary {
                if let srcs = d["sources"]?.array { for s in srcs { if let p = s.dictionary?["path"]?.string { XCTAssertTrue(p.hasPrefix(projectRoot + "/")); sawSource = true } } }
                if let res = d["resources"]?.array { for r in res { if let p = r.dictionary?["path"]?.string { XCTAssertTrue(p.hasPrefix(projectRoot + "/")); sawResource = true } } }
            }
        }
        XCTAssertTrue(sawSource)
        XCTAssertTrue(sawResource)
    }

    func testRootTargetFieldAndUnknownTargetError() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 70, userInfo: [NSLocalizedDescriptionKey: "Could not access projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 71, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // Happy path
        do {
            let q = "{ target(name: \"App\") { name type } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let data = result.data?.dictionary, let t = data["target"]?.dictionary else { XCTFail("No data"); return }
            XCTAssertEqual(t["name"]?.string, "App")
            XCTAssertEqual(t["type"]?.string, "APP")
        }
        // Unknown target -> error (GraphQL returns null field with errors)
        do {
            let q = "{ target(name: \"Nope\") { name } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            XCTAssertFalse(result.errors.isEmpty)
            let d = result.data?.dictionary
            XCTAssertNotNil(d)
            XCTAssertEqual(d?["target"], .null)
        }
    }

    func testRootDependenciesAndDependents() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 80, userInfo: [NSLocalizedDescriptionKey: "Could not access projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 81, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        let q = "{ dependencies(name: \"App\", recursive: true) { name } dependents(name: \"Lib\", recursive: true) { name } }"
        let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
        guard let data = result.data?.dictionary else { XCTFail("No data"); return }
        if let deps = data["dependencies"]?.array {
            let names = Set(deps.compactMap { $0.dictionary?["name"]?.string })
            XCTAssertEqual(names, ["Lib"])
        } else { XCTFail("Missing dependencies") }
        if let dnts = data["dependents"]?.array {
            let names = Set(dnts.compactMap { $0.dictionary?["name"]?.string })
            XCTAssertTrue(names.isSuperset(of: ["App", "AppTests"]))
        } else { XCTFail("Missing dependents") }
    }

    func testRootTargetDependenciesAndBuildScriptsFilters() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 90, userInfo: [NSLocalizedDescriptionKey: "Could not access projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 91, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // targetDependencies(recursive: true)
        do {
            let q = "{ targetDependencies(recursive: true) { target name } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let arr = result.data?.dictionary?["targetDependencies"]?.array else { XCTFail("No data"); return }
            let hasAppLib = arr.contains { v in
                if let d = v.dictionary { return d["target"]?.string == "App" && d["name"]?.string == "Lib" }
                return false
            }
            let hasTestsApp = arr.contains { v in
                if let d = v.dictionary { return d["target"]?.string == "AppTests" && d["name"]?.string == "App" }
                return false
            }
            XCTAssertTrue(hasAppLib)
            XCTAssertTrue(hasTestsApp)
        }

        // targetBuildScripts filter: POST and name prefix
        do {
            let q = "{ targetBuildScripts(filter: { stage: POST }) { target name stage } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let arr = result.data?.dictionary?["targetBuildScripts"]?.array else { XCTFail("No data"); return }
            let hasPost = arr.contains { v in v.dictionary?["target"]?.string == "App" && v.dictionary?["stage"]?.string == "POST" }
            XCTAssertTrue(hasPost)
        }
        do {
            let q = "{ targetBuildScripts(filter: { name: { prefix: \"Post\" } }) { target name } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let arr = result.data?.dictionary?["targetBuildScripts"]?.array else { XCTFail("No data"); return }
            let hasByName = arr.contains { v in
                if let d = v.dictionary { return d["target"]?.string == "App" && (d["name"]?.string ?? "").hasPrefix("Post") }
                return false
            }
            XCTAssertTrue(hasByName)
        }
    }

    func testRootTargetMembershipFileRefAndAbsolute() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let (ctx, projectRoot): (XQGQLContext, String) = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 100, userInfo: [NSLocalizedDescriptionKey: "Could not access projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
                throw NSError(domain: "GraphQLSwiftResolverTests", code: 101, userInfo: [NSLocalizedDescriptionKey: "Failed to read projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            let root = URL(fileURLWithPath: projectPath).deletingLastPathComponent().standardizedFileURL.path
            return (XQGQLContext(project: proj, projectPath: projectPath), root)
        }()

        // FILE_REF default (fileRef of Shared is just "Shared.swift")
        do {
            let q = "{ targetMembership(path: \"Shared.swift\") { path targets } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let obj = result.data?.dictionary?["targetMembership"]?.dictionary else { XCTFail("No data"); return }
            let ts = Set(obj["targets"]?.array?.compactMap { $0.string } ?? [])
            XCTAssertEqual(ts, ["App", "Lib"])
        }
        // ABSOLUTE
        do {
            let abs = URL(fileURLWithPath: projectRoot).appendingPathComponent("Shared/Shared.swift").standardizedFileURL.path
            let q = "{ targetMembership(path: \"\(abs)\", pathMode: ABSOLUTE) { path targets } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let obj = result.data?.dictionary?["targetMembership"]?.dictionary else { XCTFail("No data"); return }
            let ts = Set(obj["targets"]?.array?.compactMap { $0.string } ?? [])
            XCTAssertEqual(ts, ["App", "Lib"])
        }
    }

    func testTargetsNameStringMatchOperators() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 110, userInfo: [NSLocalizedDescriptionKey: "No projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 111, userInfo: [NSLocalizedDescriptionKey: "No projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // eq
        do {
            let q = "{ targets(filter: { name: { eq: \"App\" } }) { name } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let names = Set(result.data?.dictionary?["targets"]?.array?.compactMap { $0.dictionary?["name"]?.string } ?? [])
            XCTAssertEqual(names, ["App"])
        }
        // prefix
        do {
            let q = "{ targets(filter: { name: { prefix: \"App\" } }) { name } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let names = Set(result.data?.dictionary?["targets"]?.array?.compactMap { $0.dictionary?["name"]?.string } ?? [])
            XCTAssertTrue(names.isSuperset(of: ["App", "AppTests"]))
        }
        // suffix
        do {
            let q = "{ targets(filter: { name: { suffix: \"Tests\" } }) { name } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let names = Set(result.data?.dictionary?["targets"]?.array?.compactMap { $0.dictionary?["name"]?.string } ?? [])
            XCTAssertEqual(names, ["AppTests"])
        }
        // contains
        do {
            let q = "{ targets(filter: { name: { contains: \"pp\" } }) { name } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let names = Set(result.data?.dictionary?["targets"]?.array?.compactMap { $0.dictionary?["name"]?.string } ?? [])
            XCTAssertTrue(names.isSuperset(of: ["App", "AppTests"]))
        }
    }

    func testFlatSourcesFilterByTargetAndRegex() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 120, userInfo: [NSLocalizedDescriptionKey: "No projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 121, userInfo: [NSLocalizedDescriptionKey: "No projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        let q = #"{ targetSources(pathMode: NORMALIZED, filter: { target: { eq: "App" }, path: { regex: "\\.swift$" } }) { target path } }"#
        let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
        let arr = result.data?.dictionary?["targetSources"]?.array ?? []
        XCTAssertFalse(arr.isEmpty)
        for v in arr {
            let d = v.dictionary ?? [:]
            XCTAssertEqual(d["target"]?.string, "App")
            XCTAssertTrue(d["path"]?.string?.hasSuffix(".swift") ?? false)
        }
    }

    func testFlatResourcesFilterRegexAndTargetEq() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 130, userInfo: [NSLocalizedDescriptionKey: "No projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 131, userInfo: [NSLocalizedDescriptionKey: "No projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        let q = #"{ targetResources(filter: { path: { regex: "json$" }, target: { eq: "App" } }) { target path } }"#
        let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
        let arr = result.data?.dictionary?["targetResources"]?.array ?? []
        XCTAssertFalse(arr.isEmpty)
        for v in arr {
            let d = v.dictionary ?? [:]
            XCTAssertEqual(d["target"]?.string, "App")
            XCTAssertTrue(d["path"]?.string?.hasSuffix("json") ?? false)
        }
    }

    func testBuildScriptsFilterByNameAndTarget() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 140, userInfo: [NSLocalizedDescriptionKey: "No projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 141, userInfo: [NSLocalizedDescriptionKey: "No projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // Name contains
        do {
            let q = "{ targetBuildScripts(filter: { name: { contains: \"Pre\" }, target: { eq: \"App\" } }) { target name stage } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["targetBuildScripts"]?.array ?? []
            XCTAssertTrue(arr.contains { $0.dictionary?["name"]?.string == "Pre Script" && $0.dictionary?["target"]?.string == "App" })
        }
        // Name eq and stage PRE
        do {
            let q = "{ targetBuildScripts(filter: { name: { eq: \"Pre Script\" }, target: { eq: \"App\" }, stage: PRE }) { target name stage } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["targetBuildScripts"]?.array ?? []
            XCTAssertEqual(arr.count, 1)
            let d = arr.first?.dictionary ?? [:]
            XCTAssertEqual(d["name"]?.string, "Pre Script")
            XCTAssertEqual(d["target"]?.string, "App")
            XCTAssertEqual(d["stage"]?.string, "PRE")
        }
    }

    func testNestedSourcesFilterEqWithNormalizedPath() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 150, userInfo: [NSLocalizedDescriptionKey: "No projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 151, userInfo: [NSLocalizedDescriptionKey: "No projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        let q = "{ targets { name sources(pathMode: NORMALIZED, filter: { path: { eq: \"Shared/Shared.swift\" } }) { path } } }"
        let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
        guard let tarr = result.data?.dictionary?["targets"]?.array else { XCTFail("No data"); return }
        var libOrAppNonEmpty = false
        var testsEmpty = false
        for t in tarr {
            guard let d = t.dictionary, let name = d["name"]?.string, let arr = d["sources"]?.array else { continue }
            if name == "Lib" || name == "App" { libOrAppNonEmpty = libOrAppNonEmpty || !arr.isEmpty }
            if name == "AppTests" { testsEmpty = arr.isEmpty }
            for s in arr { XCTAssertEqual(s.dictionary?["path"]?.string, "Shared/Shared.swift") }
        }
        XCTAssertTrue(libOrAppNonEmpty)
        XCTAssertTrue(testsEmpty)
    }

    func testNestedResourcesFilterSuffixAndRegex() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 160, userInfo: [NSLocalizedDescriptionKey: "No projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 161, userInfo: [NSLocalizedDescriptionKey: "No projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // suffix: json
        do {
            let q = "{ targets { resources(filter: { path: { suffix: \"json\" } }) { path } } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let tarr = result.data?.dictionary?["targets"]?.array else { XCTFail("No data"); return }
            let some = tarr.contains { t in
                (t.dictionary?["resources"]?.array ?? []).contains { ($0.dictionary?["path"]?.string ?? "").hasSuffix("json") }
            }
            XCTAssertTrue(some)
            // Validate all returned entries end with json
            for t in tarr {
                for r in t.dictionary?["resources"]?.array ?? [] { XCTAssertTrue(r.dictionary?["path"]?.string?.hasSuffix("json") ?? false) }
            }
        }
        // regex: json$
        do {
            let q = #"{ targets { resources(filter: { path: { regex: "json$" } }) { path } } }"#
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            guard let tarr = result.data?.dictionary?["targets"]?.array else { XCTFail("No data"); return }
            let some = tarr.contains { t in
                (t.dictionary?["resources"]?.array ?? []).contains { ($0.dictionary?["path"]?.string ?? "").hasSuffix("json") }
            }
            XCTAssertTrue(some)
        }
    }

    func testTargetDependenciesFilterByTypeAndName() throws {
        let fixture = try GraphQLBaselineFixture()
        let schema = try XQGraphQLSwiftSchema.makeSchema()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let ctx: XQGQLContext = try {
            let mirror = Mirror(reflecting: fixture)
            guard let qp = mirror.children.first(where: { $0.label == "projectQuery" })?.value as? XcodeProjectQuery else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 170, userInfo: [NSLocalizedDescriptionKey: "No projectQuery"]) }
            let m = Mirror(reflecting: qp)
            guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else { throw NSError(domain: "GraphQLSwiftResolverTests", code: 171, userInfo: [NSLocalizedDescriptionKey: "No projectPath"]) }
            let proj = try XcodeProj(pathString: projectPath)
            return XQGQLContext(project: proj, projectPath: projectPath)
        }()

        // Filter by type FRAMEWORK -> should include App->Lib
        do {
            let q = "{ targetDependencies(filter: { type: FRAMEWORK }) { target name type } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["targetDependencies"]?.array ?? []
            XCTAssertTrue(arr.contains { v in v.dictionary?["target"]?.string == "App" && v.dictionary?["name"]?.string == "Lib" && v.dictionary?["type"]?.string == "FRAMEWORK" })
            // Ensure all returned types are FRAMEWORK
            for v in arr { XCTAssertEqual(v.dictionary?["type"]?.string, "FRAMEWORK") }
        }
        // Filter by name eq -> should include AppTests->App
        do {
            let q = "{ targetDependencies(filter: { name: { eq: \"App\" } }) { target name } }"
            let result = try graphql(schema: schema, request: q, context: ctx, eventLoopGroup: group).wait()
            let arr = result.data?.dictionary?["targetDependencies"]?.array ?? []
            XCTAssertTrue(arr.contains { v in v.dictionary?["target"]?.string == "AppTests" && v.dictionary?["name"]?.string == "App" })
        }
    }
}
