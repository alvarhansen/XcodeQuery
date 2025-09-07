import XCTest
import Foundation
import PathKit
import XcodeGenKit
import ProjectSpec

final class CLIIntegrationTests: XCTestCase {
    func testXCQWithGraphQLQueries() throws {
        // Arrange: make a temp project
        let tmp = try Temporary.makeTempDir()
        let projPath = Path(tmp.path) + "Sample.xcodeproj"

        // Create sources
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
                Target(
                    name: "Lib",
                    type: .framework,
                    platform: .iOS,
                    sources: [TargetSource(path: "Lib/Sources"), TargetSource(path: "Shared/Shared.swift")],
                    preBuildScripts: [BuildScript(script: .script("echo pre-lib"), name: "PreLib", inputFiles: ["$(SRCROOT)/pre.in"], outputFiles: ["$(SRCROOT)/pre.out"], inputFileLists: ["$(SRCROOT)/preInputs.xcfilelist"], outputFileLists: ["$(SRCROOT)/preOutputs.xcfilelist"])],
                    postBuildScripts: [BuildScript(script: .script("echo post-lib"), name: "PostLib")]
                ),
                Target(
                    name: "App",
                    type: .application,
                    platform: .iOS,
                    sources: [TargetSource(path: "App/Sources"), TargetSource(path: "Shared/Shared.swift")],
                    dependencies: [Dependency(type: .target, reference: "Lib")],
                    preBuildScripts: [BuildScript(script: .script("echo pre-app"), name: "PreApp")],
                    postBuildScripts: [BuildScript(script: .script("echo post-app"), name: "PostApp")]
                ),
                Target(name: "AppTests", type: .unitTestBundle, platform: .iOS, dependencies: [Dependency(type: .target, reference: "App")]),
            ]
        )
        let generator = ProjectGenerator(project: project)
        let xcodeproj = try generator.generateXcodeProject(in: Path(tmp.path), userName: "CI")
        try xcodeproj.write(path: projPath)

        // Act: run xcq CLI
        let xcqPath = try Self.locateXCQBinary()

        // 1) targets
        struct TargetsResp: Decodable { let targets: [T] }
        struct T: Decodable { let name: String, type: String }
        var (status, stdout, stderr) = try Self.run(process: xcqPath, args: ["{ targets { name type } }", "--project", projPath.string], workingDirectory: Self.packageRoot())
        if status != 0 { XCTFail("xcq failed (\(status))\nSTDERR: \(stderr)\nSTDOUT: \(stdout)"); return }
        let targets = try JSONDecoder().decode(TargetsResp.self, from: stdout.data(using: .utf8)!).targets
        let names = Set(targets.map { $0.name })
        XCTAssertTrue(names.isSuperset(of: ["App", "AppTests", "Lib"]))

        // 2) sanity: targets again via a separate run
        struct D: Decodable { let name: String }
        (status, stdout, stderr) = try Self.run(process: xcqPath, args: ["{ targets { name } }", "--project", projPath.string], workingDirectory: Self.packageRoot())
        XCTAssertEqual(status, 0)

        // 3) build scripts (flat, PRE)
        struct BSEntry: Decodable { let target: String; let name: String?; let stage: String; let inputFileListPaths: [String]; let outputFileListPaths: [String] }
        struct BSResp: Decodable { let targetBuildScripts: [BSEntry] }
        (status, stdout, stderr) = try Self.run(process: xcqPath, args: ["{ targetBuildScripts(filter: { stage: PRE }) { target name stage inputFileListPaths outputFileListPaths } }", "--project", projPath.string], workingDirectory: Self.packageRoot())
        if status != 0 { XCTFail("buildScripts failed (\(status))\nSTDERR: \(stderr)"); return }
        let bs = try JSONDecoder().decode(BSResp.self, from: stdout.data(using: .utf8)!).targetBuildScripts
        XCTAssertNotNil(bs.first(where: { $0.target == "Lib" && $0.name == "PreLib" }))

        // 4) sources for framework, regex .swift
        struct Src: Decodable { let path: String }
        struct TWithSources: Decodable { let name: String; let sources: [Src] }
        struct SResp: Decodable { let targets: [TWithSources] }
        (status, stdout, stderr) = try Self.run(process: xcqPath, args: [#"{ targets(type: FRAMEWORK) { name sources(pathMode: NORMALIZED, filter: { path: { regex: "\.swift$" } }) { path } } }"#, "--project", projPath.string], workingDirectory: Self.packageRoot())
        if status != 0 { XCTFail("sources failed (\(status))\nSTDERR: \(stderr)"); return }
        let srcOut = try JSONDecoder().decode(SResp.self, from: stdout.data(using: .utf8)!)
        let hasLibSwift = srcOut.targets.flatMap { $0.sources }.contains { $0.path.contains("LibFile.swift") }
        XCTAssertTrue(hasLibSwift)
    }

    // MARK: - Helpers
    private static func locateXCQBinary() throws -> String {
        let root = packageRoot()
        if let (code, out, _) = try? run(process: "/usr/bin/env", args: ["swift", "build", "-c", "debug", "--show-bin-path"], workingDirectory: root), code == 0 {
            let bin = out.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = URL(fileURLWithPath: bin).appendingPathComponent("xcq").path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return URL(fileURLWithPath: packageRoot()).appendingPathComponent(".build/debug/xcq").path
    }

    private static func packageRoot(file: String = #filePath) -> String {
        var url = URL(fileURLWithPath: file)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            let pkg = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: pkg.path) { return url.path }
        }
        return FileManager.default.currentDirectoryPath
    }

    @discardableResult
    private static func run(process: String, args: [String], workingDirectory: String) throws -> (Int32, String, String) {
        let proc = Process()
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        proc.executableURL = URL(fileURLWithPath: process)
        proc.arguments = args
        let outPipe = Pipe(); proc.standardOutput = outPipe
        let errPipe = Pipe(); proc.standardError = errPipe
        try proc.run(); proc.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (proc.terminationStatus, out, err)
    }
}

// Local test helpers
private enum Temporary {
    struct TempDir { let url: URL; var path: String { url.path } }
    static func makeTempDir() throws -> TempDir {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return TempDir(url: url)
    }
}
