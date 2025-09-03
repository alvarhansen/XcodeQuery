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
        try FileManager.default.createDirectory(atPath: tmp.path + "/Lib/Resources", withIntermediateDirectories: true)
        try "{\n  \"k\": \"v\"\n}".write(toFile: tmp.path + "/Lib/Resources/LibConfig.json", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: tmp.path + "/Shared", withIntermediateDirectories: true)
        try "// shared".write(toFile: tmp.path + "/Shared/Shared.swift", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: tmp.path + "/App/Sources", withIntermediateDirectories: true)
        try "// app".write(toFile: tmp.path + "/App/Sources/AppFile.swift", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: tmp.path + "/App/Resources", withIntermediateDirectories: true)
        try "{}".write(toFile: tmp.path + "/App/Resources/AppConfig.json", atomically: true, encoding: .utf8)

        let project = Project(
            basePath: Path(tmp.path),
            name: "Sample",
            targets: [
                Target(
                    name: "Lib",
                    type: .framework,
                    platform: .iOS,
                    sources: [
                        TargetSource(path: "Lib/Sources"),
                        TargetSource(path: "Shared/Shared.swift"),
                        TargetSource(path: "Lib/Resources/LibConfig.json", buildPhase: .resources),
                    ],
                    preBuildScripts: [BuildScript(script: .script("echo pre-lib"), name: "PreLib", inputFiles: ["$(SRCROOT)/pre.in"], outputFiles: ["$(SRCROOT)/pre.out"], inputFileLists: ["$(SRCROOT)/preInputs.xcfilelist"], outputFileLists: ["$(SRCROOT)/preOutputs.xcfilelist"])],
                    postBuildScripts: [BuildScript(script: .script("echo post-lib"), name: "PostLib", inputFiles: ["$(SRCROOT)/post.in"], outputFiles: ["$(SRCROOT)/post.out"])]
                ),
                Target(
                    name: "App",
                    type: .application,
                    platform: .iOS,
                    sources: [
                        TargetSource(path: "App/Sources"),
                        TargetSource(path: "Shared/Shared.swift"),
                        TargetSource(path: "App/Resources/AppConfig.json", buildPhase: .resources),
                    ],
                    dependencies: [Dependency(type: .target, reference: "Lib")],
                    preBuildScripts: [BuildScript(script: .script("echo pre-app"), name: "PreApp")],
                    postBuildScripts: [BuildScript(script: .script("echo post-app"), name: "PostApp")]
                ),
                Target(name: "AppTests", type: .unitTestBundle, platform: .iOS, dependencies: [Dependency(type: .target, reference: "App")]),
                Target(name: "AppUITests", type: .uiTestBundle, platform: .iOS, dependencies: [Dependency(type: .target, reference: "App")]),
            ],
            fileGroups: ["Unowned.swift"]
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

        // sources(App, pathMode: "absolute") -> absolute path endswith AppFile.swift
        do {
            let any = try qp.evaluate(query: ".sources(\"App\", pathMode: \"absolute\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.SourceEntry].self, from: data)
            XCTAssertTrue(results.allSatisfy { $0.path.hasPrefix("/") })
            XCTAssertTrue(results.contains(where: { $0.path.hasSuffix("AppFile.swift") }))
        }

        // pipeline: frameworks | sources(pathMode: "normalized") -> relative paths like Lib/Sources/LibFile.swift
        do {
            let any = try qp.evaluate(query: ".targets[] | filter(.type == .framework) | sources(pathMode: \"normalized\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.SourceEntry].self, from: data)
            XCTAssertTrue(results.allSatisfy { !$0.path.hasPrefix("/") })
            XCTAssertTrue(results.contains(where: { $0.path.contains("Lib/Sources/LibFile.swift") }))
            XCTAssertFalse(results.contains(where: { $0.path.hasPrefix("./") }))
        }

        // targetMembership for Lib file (normalized)
        do {
            let any = try qp.evaluate(query: ".targetMembership(\"Lib/Sources/LibFile.swift\", pathMode: \"normalized\")")
            let data = try JSONEncoder().encode(any)
            let result = try JSONDecoder().decode(XcodeQueryKit.OwnerEntry.self, from: data)
            XCTAssertEqual(result.path, "Lib/Sources/LibFile.swift")
            XCTAssertEqual(Set(result.targets), ["Lib"])
        }

        // Using pipeline targetMembership: Shared/Shared.swift should appear with two targets
        do {
            let any = try qp.evaluate(query: ".targets[] | sources(pathMode: \"normalized\") | targetMembership")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.OwnerEntry].self, from: data)
            let entry = results.first { $0.path.contains("Shared/Shared.swift") }
            XCTAssertNotNil(entry)
            XCTAssertEqual(Set(entry!.targets), ["App", "Lib"])
        }

        // A file that is not in any target reports empty membership
        do {
            try "// unowned".write(toFile: tmp.path + "/Unowned.swift", atomically: true, encoding: .utf8)
            // Note: add to project navigator but not to any target
            let any = try qp.evaluate(query: ".targetMembership(\"Unowned.swift\", pathMode: \"normalized\")")
            let data = try JSONEncoder().encode(any)
            let result = try JSONDecoder().decode(XcodeQueryKit.OwnerEntry.self, from: data)
            XCTAssertEqual(result.path, "Unowned.swift")
            XCTAssertTrue(result.targets.isEmpty)
        }

        // buildScripts(App) contains pre and post entries
        do {
            let any = try qp.evaluate(query: ".buildScripts(\"App\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.BuildScriptEntry].self, from: data)
            let names = Set(results.compactMap { $0.name })
            XCTAssertTrue(names.contains("PreApp"))
            XCTAssertTrue(names.contains("PostApp"))
            let preStages = results.filter { $0.name == "PreApp" }.map { $0.stage }
            XCTAssertTrue(preStages.contains(.pre))
        }

        // pipeline: .targets[] | filter(.type == .framework) | buildScripts -> contains PreLib
        do {
            let any = try qp.evaluate(query: ".targets[] | filter(.type == .framework) | buildScripts")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.BuildScriptEntry].self, from: data)
            XCTAssertTrue(results.contains(where: { $0.target == "Lib" && $0.name == "PreLib" }))
            // input file lists exist
            let preLib = results.first(where: { $0.target == "Lib" && $0.name == "PreLib" })!
            XCTAssertFalse(preLib.inputFileListPaths.isEmpty)
            XCTAssertFalse(preLib.outputFileListPaths.isEmpty)
        }

        // REGEX: target name matches ^App(Tests)?$
        do {
            let any = try qp.evaluate(query: ".targets[] | filter(.name ~= \"^App(Tests)?$\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.Target].self, from: data)
            let names = Set(results.map { $0.name })
            XCTAssertTrue(names.contains("App"))
            XCTAssertTrue(names.contains("AppTests"))
            XCTAssertFalse(names.contains("AppUITests"))
        }

        // REGEX: sources path ends with .swift
        do {
            let any = try qp.evaluate(query: ".targets[] | sources | filter(.path ~= \"\\.swift$\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.SourceEntry].self, from: data)
            XCTAssertTrue(results.contains(where: { $0.path.contains("AppFile.swift") }))
            XCTAssertTrue(results.contains(where: { $0.path.contains("LibFile.swift") }))
        }

        // REGEX: sources target == ^Lib$
        do {
            let any = try qp.evaluate(query: ".targets[] | sources | filter(.target ~= \"^Lib$\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.SourceEntry].self, from: data)
            XCTAssertTrue(results.allSatisfy { $0.target == "Lib" })
        }

        // REGEX: buildScripts name starts with Pre
        do {
            let any = try qp.evaluate(query: ".targets[] | buildScripts | filter(.name ~= \"^Pre\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.BuildScriptEntry].self, from: data)
            let names = Set(results.compactMap { $0.name })
            XCTAssertTrue(names.contains("PreApp"))
            XCTAssertTrue(names.contains("PreLib"))
            XCTAssertFalse(names.contains("PostApp"))
        }

        // LITERAL equality must not require escaping '.' in filename
        do {
            let any = try qp.evaluate(query: ".targets[] | sources | filter(.path == \"LibFile.swift\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([XcodeQueryKit.SourceEntry].self, from: data)
            XCTAssertTrue(results.contains(where: { $0.path == "Lib/Sources/LibFile.swift" || $0.path == "LibFile.swift" }))
        }

        // RESOURCES: direct call and pipeline with filters
        do {
            let any = try qp.evaluate(query: ".resources(\"App\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([ResourceEntry].self, from: data)
            XCTAssertTrue(results.contains(where: { $0.target == "App" && $0.path.contains("AppConfig.json") }))
        }

        do {
            let any = try qp.evaluate(query: ".targets[] | resources | filter(.path == \"LibConfig.json\")")
            let data = try JSONEncoder().encode(any)
            let results = try JSONDecoder().decode([ResourceEntry].self, from: data)
            XCTAssertTrue(results.contains(where: { $0.target == "Lib" && ($0.path == "Lib/Resources/LibConfig.json" || $0.path == "LibConfig.json") }))
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
