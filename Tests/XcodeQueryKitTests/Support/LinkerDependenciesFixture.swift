import XCTest
import Foundation
import PathKit
import ProjectSpec
import XcodeGenKit
@testable import XcodeQueryKit

struct LinkerDependenciesFixture {
    private let tempDirectory: URL
    private let projectQuery: XcodeProjectQuery

    init() throws {
        let uuid = UUID().uuidString
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("LinkDeps-\(uuid)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        self.tempDirectory = tempRoot

        try LinkerDependenciesFixture.populateFiles(at: tempRoot)

        let project = LinkerDependenciesFixture.makeProject(basePath: tempRoot)
        let generator = ProjectGenerator(project: project)
        let projPath = Path(tempRoot.path) + "LinkDeps.xcodeproj"
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
            throw NSError(domain: "LinkerDependenciesFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON output"])
        }
        if !string.hasSuffix("\n") { string.append("\n") }
        return string
    }

    private static func populateFiles(at root: URL) throws {
        // App sources
        try FileManager.default.createDirectory(at: root.appendingPathComponent("App/Sources", isDirectory: true), withIntermediateDirectories: true)
        try "// app".write(to: root.appendingPathComponent("App/Sources/App.swift"), atomically: true, encoding: .utf8)
        // Create a dummy local framework directory to reference
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Vendor/Local.framework", isDirectory: true), withIntermediateDirectories: true)
    }

    private static func makeProject(basePath: URL) -> Project {
        var app = Target(
            name: "App",
            type: .application,
            platform: .iOS,
            sources: [TargetSource(path: "App/Sources")],
            dependencies: [],
            preBuildScripts: [],
            postCompileScripts: [],
            postBuildScripts: []
        )

        // Link a local framework and embed it
        app.dependencies.append(Dependency(type: .framework, reference: "Vendor/Local.framework", embed: true))
        // Link an SDK framework (UIKit)
        app.dependencies.append(Dependency(type: .sdk(root: nil), reference: "UIKit.framework", weakLink: true))
        // Add a Swift package product for classification
        let packages: [String: SwiftPackage] = [
            "A": .remote(url: "https://github.com/acme/A", versionRequirement: .exact("1.2.3"))
        ]
        app.dependencies.append(Dependency(type: .package(products: ["ACore"]), reference: "A"))

        let project = Project(
            basePath: Path(basePath.path),
            name: "LinkDeps",
            targets: [app],
            settings: Settings(dictionary: [:]),
            packages: packages
        )
        return project
    }
}

