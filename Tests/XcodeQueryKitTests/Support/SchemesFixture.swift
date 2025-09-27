import XCTest
import Foundation
import PathKit
import ProjectSpec
import XcodeGenKit
import XcodeProj
@testable import XcodeQueryKit

struct SchemesFixture {
    private let projectQuery: XcodeProjectQuery

    init() throws {
        let uuid = UUID().uuidString
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Schemes-\(uuid)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        try SchemesFixture.populateFiles(at: tempRoot)

        let project = SchemesFixture.makeProject(basePath: tempRoot)
        let generator = ProjectGenerator(project: project)
        let projPath = Path(tempRoot.path) + "SchemesSample.xcodeproj"
        let xcodeproj = try generator.generateXcodeProject(in: Path(tempRoot.path), userName: "CI")
        try xcodeproj.write(path: projPath)

        self.projectQuery = XcodeProjectQuery(projectPath: projPath.string)
    }

    func makeContext() throws -> XQGQLContext {
        // Reflect to extract projectPath
        let m = Mirror(reflecting: projectQuery)
        guard let projectPath = m.children.first(where: { $0.label == "projectPath" })?.value as? String else {
            throw NSError(domain: "SchemesFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No projectPath"]) }
        let proj = try XcodeProj(pathString: projectPath)
        return XQGQLContext(project: proj, projectPath: projectPath)
    }

    private static func populateFiles(at root: URL) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("App/Sources", isDirectory: true), withIntermediateDirectories: true)
        try "// app".write(to: root.appendingPathComponent("App/Sources/App.swift"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Lib/Sources", isDirectory: true), withIntermediateDirectories: true)
        try "// lib".write(to: root.appendingPathComponent("Lib/Sources/Lib.swift"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("AppTests/Sources", isDirectory: true), withIntermediateDirectories: true)
        try "// tests".write(to: root.appendingPathComponent("AppTests/Sources/Tests.swift"), atomically: true, encoding: .utf8)
    }

    private static func makeProject(basePath: URL) -> Project {
        let app = Target(
            name: "App",
            type: .application,
            platform: .iOS,
            sources: [TargetSource(path: "App/Sources")]
        )
        let lib = Target(
            name: "Lib",
            type: .framework,
            platform: .iOS,
            sources: [TargetSource(path: "Lib/Sources")]
        )
        var tests = Target(
            name: "AppTests",
            type: .unitTestBundle,
            platform: .iOS,
            sources: [TargetSource(path: "AppTests/Sources")]
        )
        tests.dependencies = [Dependency(type: .target, reference: "App")]

        // Define two shared schemes
        let appScheme = Scheme(
            name: "AppScheme",
            build: .init(targets: [
                .init(target: .local("App")),
                .init(target: .local("Lib"))
            ]),
            run: .init(macroExpansion: "App"),
            test: .init(targets: ["AppTests"])
        )
        let libScheme = Scheme(
            name: "LibScheme",
            build: .init(targets: [ .init(target: .local("Lib")) ]),
            run: nil,
            test: nil
        )

        let project = Project(
            basePath: Path(basePath.path),
            name: "SchemesSample",
            targets: [app, lib, tests],
            schemes: [appScheme, libScheme]
        )
        return project
    }
}
