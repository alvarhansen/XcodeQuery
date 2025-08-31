import XCTest
@testable import XcodeQueryKit
import XcodeGenKit
import ProjectSpec
import PathKit

final class XcodeQueryKitTests: XCTestCase {
    func testTargetsAndFilters() throws {
        // 1) Create a temporary directory
        let tmp = try Temporary.makeTempDir()
        let xcodeprojPath = Path(tmp.path) + "Sample.xcodeproj"

        // 2) Build a ProjectSpec model programmatically and generate .xcodeproj via XcodeGenKit
        // Create some source files for targets
        try FileManager.default.createDirectory(atPath: tmp.path + "/Lib/Sources", withIntermediateDirectories: true)
        try "// lib".write(toFile: tmp.path + "/Lib/Sources/LibFile.swift", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: tmp.path + "/App/Sources", withIntermediateDirectories: true)
        try "// app".write(toFile: tmp.path + "/App/Sources/AppFile.swift", atomically: true, encoding: .utf8)

        let project = Project(
            basePath: Path(tmp.path),
            name: "Sample",
            targets: [
                Target(name: "Lib", type: .framework, platform: .iOS, sources: [TargetSource(path: "Lib/Sources")]),
                Target(name: "App", type: .application, platform: .iOS, sources: [TargetSource(path: "App/Sources")], dependencies: [Dependency(type: .target, reference: "Lib")]),
                Target(name: "AppTests", type: .unitTestBundle, platform: .iOS, dependencies: [Dependency(type: .target, reference: "App")]),
                Target(name: "AppUITests", type: .uiTestBundle, platform: .iOS, dependencies: [Dependency(type: .target, reference: "App")]),
            ]
        )
        let generator = ProjectGenerator(project: project)
        let xcodeproj = try generator.generateXcodeProject(in: Path(tmp.path), userName: "CI")
        try xcodeproj.write(path: xcodeprojPath)

        // 3) Run queries against the generated project
        let qp = XcodeProjectQuery(projectPath: xcodeprojPath.string)

        // .targets
        do {
            let any = try qp.evaluate(query: ".targets")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.Target].self, from: data)
            let names = Set(results.map { $0.name })
            XCTAssertTrue(names.contains("App"))
            XCTAssertTrue(names.contains("AppTests"))
            XCTAssertTrue(names.contains("AppUITests"))
            XCTAssertTrue(names.contains("Lib"))
        }

        // filter by suffix
        do {
            let any = try qp.evaluate(query: ".targets[] | filter(.name.hasSuffix(\"Tests\"))")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.Target].self, from: data)
            let names = results.map { $0.name }
            XCTAssertTrue(names.contains("AppTests"))
            XCTAssertFalse(names.contains("App"))
        }

        // filter by type
        do {
            let any = try qp.evaluate(query: ".targets[] | filter(.type == .unitTest)")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.Target].self, from: data)
            XCTAssertEqual(results.map { $0.type }, Array(repeating: XcodeQueryKit.TargetType.unitTest, count: results.count))
        }

        // dependencies(App) -> [Lib]
        do {
            let any = try qp.evaluate(query: ".dependencies(\"App\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.Target].self, from: data)
            let names = Set(results.map { $0.name })
            XCTAssertEqual(names, ["Lib"])
        }

        // dependencies(AppTests, recursive: true) -> [App, Lib]
        do {
            let any = try qp.evaluate(query: ".dependencies(\"AppTests\", recursive: true)")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.Target].self, from: data)
            let names = Set(results.map { $0.name })
            XCTAssertEqual(names, ["App", "Lib"])
        }

        // dependents(Lib) -> [App]
        do {
            let any = try qp.evaluate(query: ".dependents(\"Lib\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.Target].self, from: data)
            let names = Set(results.map { $0.name })
            XCTAssertEqual(names, ["App"])
        }

        // dependents(Lib, recursive: true) -> [App, AppTests, AppUITests]
        do {
            let any = try qp.evaluate(query: ".dependents(\"Lib\", recursive: true)")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.Target].self, from: data)
            let names = Set(results.map { $0.name })
            XCTAssertEqual(names, ["App", "AppTests", "AppUITests"])
        }

        // reverseDependencies alias should work the same
        do {
            let any = try qp.evaluate(query: ".reverseDependencies(\"Lib\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.Target].self, from: data)
            let names = Set(results.map { $0.name })
            XCTAssertEqual(names, ["App"])
        }

        // pipeline: .targets[] | filter(.type == .app) | dependencies -> [Lib]
        do {
            let any = try qp.evaluate(query: ".targets[] | filter(.type == .app) | dependencies")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.Target].self, from: data)
            let names = Set(results.map { $0.name })
            XCTAssertEqual(names, ["Lib"])
        }

        // pipeline recursive: unit tests -> dependencies(recursive: true) -> [App, Lib]
        do {
            let any = try qp.evaluate(query: ".targets[] | filter(.type == .unitTest) | dependencies(recursive: true)")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.Target].self, from: data)
            let names = Set(results.map { $0.name })
            XCTAssertEqual(names, ["App", "Lib"])
        }

        // pipeline dependents: framework -> dependents -> [App]
        do {
            let any = try qp.evaluate(query: ".targets[] | filter(.type == .framework) | dependents")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.Target].self, from: data)
            let names = Set(results.map { $0.name })
            XCTAssertEqual(names, ["App"])
        }

        // pipeline dependents recursive: framework -> dependents(recursive: true) -> [App, AppTests, AppUITests]
        do {
            let any = try qp.evaluate(query: ".targets[] | filter(.type == .framework) | dependents(recursive: true)")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.Target].self, from: data)
            let names = Set(results.map { $0.name })
            XCTAssertEqual(names, ["App", "AppTests", "AppUITests"])
        }

        // sources(App) -> one entry pointing to AppFile.swift
        do {
            let any = try qp.evaluate(query: ".sources(\"App\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.SourceEntry].self, from: data)
            XCTAssertTrue(results.contains(where: { $0.target == "App" && $0.path.contains("AppFile.swift") }))
        }

        // pipeline: .targets[] | filter(.type == .framework) | sources -> includes LibFile.swift
        do {
            let any = try qp.evaluate(query: ".targets[] | filter(.type == .framework) | sources")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.SourceEntry].self, from: data)
            XCTAssertTrue(results.contains(where: { $0.target == "Lib" && $0.path.contains("LibFile.swift") }))
        }
    }
}

// MARK: - Test helpers

private enum Temporary {
    struct TempDir {
        let url: URL
        var path: String { url.path }
        func appending(pathComponent: String) -> URL { url.appendingPathComponent(pathComponent) }
    }

    static func makeTempDir() throws -> TempDir {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return TempDir(url: url)
    }
}
