import XCTest
import Foundation
import PathKit
import XcodeGenKit
import ProjectSpec
@testable import XcodeQueryKit

final class GraphQLTests: XCTestCase {
    func testGraphQLQueries() throws {
        // Arrange sample project
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
                Target(name: "AppTests", type: .unitTestBundle, platform: .iOS, dependencies: [Dependency(type: .target, reference: "App")])
            ]
        )
        let generator = ProjectGenerator(project: project)
        let xcodeproj = try generator.generateXcodeProject(in: Path(tmp.path), userName: "CI")
        try xcodeproj.write(path: projPath)

        let qp = XcodeProjectQuery(projectPath: projPath.string)

        // targets
        do {
            let any = try qp.evaluate(query: "{ targets { name type } }")
            let data = try JSONEncoder().encode(any)
            struct Root: Decodable { struct T: Decodable { let name: String; let type: String }; let targets: [T] }
            let obj = try JSONDecoder().decode(Root.self, from: data)
            let names = Set(obj.targets.map { $0.name })
            XCTAssertEqual(names, ["App", "AppTests", "Lib"])
        }

        // dependencies(App) -> Lib
        do {
            let any = try qp.evaluate(query: "{ dependencies(name: \"App\") { name } }")
            let data = try JSONEncoder().encode(any)
            struct Root: Decodable { struct D: Decodable { let name: String }; let dependencies: [D] }
            let out = try JSONDecoder().decode(Root.self, from: data)
            XCTAssertEqual(Set(out.dependencies.map { $0.name }), ["Lib"])
        }

        // targetSources normalized contain files
        do {
            let any = try qp.evaluate(query: "{ targetSources(pathMode: NORMALIZED) { target path } }")
            let data = try JSONEncoder().encode(any)
            struct Root: Decodable { struct Row: Decodable { let target: String; let path: String }; let targetSources: [Row] }
            let out = try JSONDecoder().decode(Root.self, from: data)
            XCTAssertTrue(out.targetSources.contains(where: { $0.target == "App" && $0.path.contains("App/Sources/AppFile.swift") }))
            XCTAssertTrue(out.targetSources.contains(where: { $0.target == "Lib" && $0.path.contains("Lib/Sources/LibFile.swift") }))
        }

        // membership for Shared.swift has two owners
        do {
            let any = try qp.evaluate(query: "{ targetMembership(path: \"Shared/Shared.swift\", pathMode: NORMALIZED) { path targets } }")
            let data = try JSONEncoder().encode(any)
            struct Root: Decodable { struct M: Decodable { let path: String; let targets: [String] }; let targetMembership: M }
            let out = try JSONDecoder().decode(Root.self, from: data)
            XCTAssertEqual(out.targetMembership.path, "Shared/Shared.swift")
            XCTAssertEqual(Set(out.targetMembership.targets), ["App", "Lib"])
        }
    }
}

// MARK: - Test helpers
private enum Temporary {
    struct TempDir { let url: URL; var path: String { url.path } }
    static func makeTempDir() throws -> TempDir {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return TempDir(url: url)
    }
}

