import XCTest
@testable import XcodeQueryKit
import XcodeGenKit
import ProjectSpec
import PathKit

final class GraphQLQueryTests: XCTestCase {
    func testGraphQLQueriesAgainstGeneratedProject() throws {
        // Arrange project
        let tmp = try Temporary.makeTempDir()
        let projPath = Path(tmp.path) + "Sample.xcodeproj"

        try FileManager.default.createDirectory(atPath: tmp.path + "/Lib/Sources", withIntermediateDirectories: true)
        try "// lib".write(toFile: tmp.path + "/Lib/Sources/LibFile.swift", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: tmp.path + "/App/Sources", withIntermediateDirectories: true)
        try "// app".write(toFile: tmp.path + "/App/Sources/AppFile.swift", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: tmp.path + "/Shared", withIntermediateDirectories: true)
        try "// shared".write(toFile: tmp.path + "/Shared/Shared.swift", atomically: true, encoding: .utf8)

        let project = Project(
            basePath: Path(tmp.path),
            name: "Sample",
            targets: [
                Target(name: "Lib", type: .framework, platform: .iOS, sources: [TargetSource(path: "Lib/Sources"), TargetSource(path: "Shared/Shared.swift")]),
                Target(name: "App", type: .application, platform: .iOS, sources: [TargetSource(path: "App/Sources"), TargetSource(path: "Shared/Shared.swift")], dependencies: [Dependency(type: .target, reference: "Lib")]),
                Target(name: "AppTests", type: .unitTestBundle, platform: .iOS, dependencies: [Dependency(type: .target, reference: "App")]),
            ]
        )
        let generator = ProjectGenerator(project: project)
        let xcodeproj = try generator.generateXcodeProject(in: Path(tmp.path), userName: "CI")
        try xcodeproj.write(path: projPath)

        let qp = XcodeProjectQuery(projectPath: projPath.string)

        // 1) Targets list
        struct TargetsOut: Decodable { let targets: [T] }
        struct T: Decodable { let name: String; let type: String }
        let anyTargets = try qp.evaluate(query: "targets { name type }")
        let targetData = try JSONEncoder().encode(anyTargets)
        let targets = try JSONDecoder().decode(TargetsOut.self, from: targetData).targets
        XCTAssertTrue(Set(targets.map { $0.name }).isSuperset(of: ["App", "AppTests", "Lib"]))

        // 2) Basic flat view (targetSources)
        struct Row: Decodable { let target: String; let path: String }
        struct Flat: Decodable { let targetSources: [Row] }
        let anyFlat = try qp.evaluate(query: "targetSources(pathMode: NORMALIZED) { target path }")
        let flat = try JSONDecoder().decode(Flat.self, from: JSONEncoder().encode(anyFlat)).targetSources
        XCTAssertTrue(flat.contains(where: { $0.target == "Lib" && $0.path.contains("Lib/Sources/LibFile.swift") }))

        // 3) Unit test transitive deps -> [App, Lib]
        struct D: Decodable { let name: String }
        struct WithDeps: Decodable { let name: String; let dependencies: [D] }
        struct NestedOut: Decodable { let targets: [WithDeps] }
        let anyNested = try qp.evaluate(query: "targets(type: UNIT_TEST) { name dependencies(recursive: true) { name } }")
        let nested = try JSONDecoder().decode(NestedOut.self, from: JSONEncoder().encode(anyNested))
        let depsFlat = Set(nested.targets.flatMap { $0.dependencies.map { $0.name } })
        XCTAssertEqual(depsFlat, ["App", "Lib"])

        // 4) Sources regex filter
        struct Src: Decodable { let path: String }
        struct TS: Decodable { let name: String; let sources: [Src] }
        struct SOut: Decodable { let targets: [TS] }
        let anySrc = try qp.evaluate(query: #"targets(type: FRAMEWORK) { name sources(pathMode: NORMALIZED, filter: { path: { regex: "\\.swift$" } }) { path } }"#)
        let src = try JSONDecoder().decode(SOut.self, from: JSONEncoder().encode(anySrc))
        XCTAssertTrue(src.targets.flatMap { $0.sources }.contains { $0.path.contains("LibFile.swift") })
    }
}

private enum Temporary {
    struct TempDir { let url: URL; var path: String { url.path } }
    static func makeTempDir() throws -> TempDir {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return TempDir(url: url)
    }
}

