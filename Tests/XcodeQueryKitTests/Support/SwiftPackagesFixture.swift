import XCTest
import Foundation
import PathKit
import ProjectSpec
import XcodeGenKit
@testable import XcodeQueryKit

struct SwiftPackagesFixture {
    private let tempDirectory: URL
    private let projectQuery: XcodeProjectQuery

    init() throws {
        let uuid = UUID().uuidString
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftPackages-\(uuid)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        self.tempDirectory = tempRoot

        try SwiftPackagesFixture.populateFiles(at: tempRoot)

        let project = SwiftPackagesFixture.makeProject(basePath: tempRoot)
        let generator = ProjectGenerator(project: project)
        let projPath = Path(tempRoot.path) + "PkgSample.xcodeproj"
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
            throw NSError(domain: "SwiftPackagesFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON output"])
        }
        if !string.hasSuffix("\n") { string.append("\n") }
        return string
    }

    private static func populateFiles(at root: URL) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("App/Sources", isDirectory: true), withIntermediateDirectories: true)
        try "// app".write(to: root.appendingPathComponent("App/Sources/AppFile.swift"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Tool/Sources", isDirectory: true), withIntermediateDirectories: true)
        try "// tool".write(to: root.appendingPathComponent("Tool/Sources/ToolMain.swift"), atomically: true, encoding: .utf8)
    }

    private static func makeProject(basePath: URL) -> Project {
        var app = Target(
            name: "App",
            type: .application,
            platform: .macOS,
            sources: [TargetSource(path: "App/Sources")],
            dependencies: [],
            preBuildScripts: [],
            postCompileScripts: [],
            postBuildScripts: []
        )
        var tool = Target(
            name: "Tool",
            type: .commandLineTool,
            platform: .macOS,
            sources: [TargetSource(path: "Tool/Sources")]
        )
        let tests = Target(
            name: "AppTests",
            type: .unitTestBundle,
            platform: .macOS,
            sources: []
        )

        // Add package dependencies by name -> products
        app.dependencies.append(Dependency(type: .package(products: ["ACore"]), reference: "A"))
        app.dependencies.append(Dependency(type: .package(products: ["BUI"]), reference: "B"))
        tool.dependencies.append(Dependency(type: .package(products: ["BTool"]), reference: "B"))
        var testsMut = tests
        testsMut.dependencies.append(Dependency(type: .package(products: ["ACore"]), reference: "A"))

        let packages: [String: SwiftPackage] = [
            "A": .remote(url: "https://github.com/acme/A", versionRequirement: .exact("1.2.3")),
            "B": .remote(url: "https://github.com/acme/B", versionRequirement: .upToNextMajorVersion("2.0.0"))
        ]

        let project = Project(
            basePath: Path(basePath.path),
            name: "PkgSample",
            targets: [app, tool, testsMut],
            settings: Settings(dictionary: [:]),
            packages: packages
        )
        return project
    }
}

