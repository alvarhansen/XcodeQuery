import XCTest
import Foundation
import PathKit
import ProjectSpec
import XcodeGenKit
@testable import XcodeQueryKit

struct GraphQLBaselineFixture {
    private let tempDirectory: URL
    private let projectQuery: XcodeProjectQuery

    init() throws {
        let uuid = UUID().uuidString
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("GraphQLBaseline-\(uuid)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        self.tempDirectory = tempRoot

        try GraphQLBaselineFixture.populateFixtureFiles(at: tempRoot)

        let project = GraphQLBaselineFixture.makeProjectSpec(basePath: tempRoot)
        let generator = ProjectGenerator(project: project)
        let projPath = Path(tempRoot.path) + "Sample.xcodeproj"
        let xcodeproj = try generator.generateXcodeProject(in: Path(tempRoot.path), userName: "CI")
        try xcodeproj.write(path: projPath)

        self.projectQuery = XcodeProjectQuery(projectPath: projPath.string)
    }

    func evaluateToCanonicalJSON(query: String) throws -> String {
        let result = try projectQuery.evaluate(query: query)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        guard var string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "GraphQLBaselineFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON output"])
        }
        if !string.hasSuffix("\n") { string.append("\n") }
        return string
    }

    private static func populateFixtureFiles(at root: URL) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Lib/Sources", isDirectory: true), withIntermediateDirectories: true)
        try "// lib".write(to: root.appendingPathComponent("Lib/Sources/LibFile.swift"), atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: root.appendingPathComponent("App/Sources", isDirectory: true), withIntermediateDirectories: true)
        try "// app".write(to: root.appendingPathComponent("App/Sources/AppFile.swift"), atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: root.appendingPathComponent("Shared", isDirectory: true), withIntermediateDirectories: true)
        try "// shared".write(to: root.appendingPathComponent("Shared/Shared.swift"), atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: root.appendingPathComponent("Resources", isDirectory: true), withIntermediateDirectories: true)
        try "{\"config\":true}".write(to: root.appendingPathComponent("Resources/Config.json"), atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: root.appendingPathComponent("Scripts", isDirectory: true), withIntermediateDirectories: true)
        try "echo pre".write(to: root.appendingPathComponent("Scripts/pre.sh"), atomically: true, encoding: .utf8)
        try "echo post".write(to: root.appendingPathComponent("Scripts/post.sh"), atomically: true, encoding: .utf8)
    }

    private static func makeProjectSpec(basePath: URL) -> Project {
        let libTarget = Target(
            name: "Lib",
            type: .framework,
            platform: .iOS,
            sources: [
                TargetSource(path: "Lib/Sources"),
                TargetSource(path: "Shared/Shared.swift")
            ],
            dependencies: [],
            preBuildScripts: [],
            postCompileScripts: [],
            postBuildScripts: []
        )

        var appTarget = Target(
            name: "App",
            type: .application,
            platform: .iOS,
            sources: [
                TargetSource(path: "App/Sources"),
                TargetSource(path: "Shared/Shared.swift")
            ],
            dependencies: [Dependency(type: .target, reference: "Lib")],
            preBuildScripts: [
                BuildScript(
                    script: .path("Scripts/pre.sh"),
                    name: "Pre Script",
                    inputFiles: ["$(SRCROOT)/Shared/Shared.swift"]
                )
            ],
            postCompileScripts: [
                BuildScript(
                    script: .path("Scripts/post.sh"),
                    name: "Post Script",
                    outputFiles: ["$(BUILT_PRODUCTS_DIR)/Generated.txt"]
                )
            ],
            postBuildScripts: []
        )
        // Add some target-level settings to exercise targetBuildSettings
        appTarget.settings = Settings(dictionary: [
            "SWIFT_VERSION": "5.10",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["DEBUG", "APP_CUSTOM"]
        ])

        let testsTarget = Target(
            name: "AppTests",
            type: .unitTestBundle,
            platform: .iOS,
            sources: [],
            dependencies: [Dependency(type: .target, reference: "App")]
        )

        let project = Project(
            basePath: Path(basePath.path),
            name: "Sample",
            targets: [
                libTarget.addingResources(),
                appTarget.addingResources(),
                testsTarget
            ],
            settings: Settings(dictionary: [
                "SWIFT_VERSION": "5.9",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["DEBUG"]
            ])
        )
        return project
    }
}

private extension ProjectSpec.Target {
    func addingResources() -> ProjectSpec.Target {
        var updated = self
        updated.sources.append(TargetSource(path: "Resources/Config.json", buildPhase: .resources))
        return updated
    }
}

enum GraphQLSnapshot {
    private static let recordEnv = "XCQ_RECORD_GRAPHQL_SNAPSHOTS"
    private static let snapshotsRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Tests/XcodeQueryKitTests/Snapshots", isDirectory: true)

    static func assertSnapshot(data: String, named name: String, subdirectory: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let dir = snapshotsRoot.appendingPathComponent(subdirectory, isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let url = dir.appendingPathComponent("\(name).json", isDirectory: false)
        if ProcessInfo.processInfo.environment[recordEnv] != nil {
            try data.data(using: .utf8)?.write(to: url, options: .atomic)
            return
        }
        guard fm.fileExists(atPath: url.path) else {
            XCTFail("Missing snapshot at \(url.path). Set \(recordEnv)=1 to record.", file: file, line: line)
            return
        }
        let expectedData = try Data(contentsOf: url)
        guard let expected = String(data: expectedData, encoding: .utf8) else {
            XCTFail("Snapshot at \(url.path) is not valid UTF-8", file: file, line: line)
            return
        }
        XCTAssertEqual(data, expected, file: file, line: line)
    }
}
