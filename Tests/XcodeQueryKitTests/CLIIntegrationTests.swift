import XCTest
import Foundation
import PathKit
import XcodeGenKit
import ProjectSpec

final class CLIIntegrationTests: XCTestCase {
    func testXQListsTargetsFromGeneratedProject() throws {
        // Arrange: make a temp project
        let tmp = try Temporary.makeTempDir()
        let projPath = Path(tmp.path) + "Sample.xcodeproj"

        let project = Project(
            basePath: Path(tmp.path),
            name: "Sample",
            targets: [
                Target(name: "Lib", type: .framework, platform: .iOS),
                Target(name: "App", type: .application, platform: .iOS, dependencies: [Dependency(type: .target, reference: "Lib")]),
                Target(name: "AppTests", type: .unitTestBundle, platform: .iOS, dependencies: [Dependency(type: .target, reference: "App")]),
                Target(name: "AppUITests", type: .uiTestBundle, platform: .iOS, dependencies: [Dependency(type: .target, reference: "App")]),
            ]
        )
        let generator = ProjectGenerator(project: project)
        let xcodeproj = try generator.generateXcodeProject(in: Path(tmp.path), userName: "CI")
        try xcodeproj.write(path: projPath)

        // Act: run xq CLI
        let xqPath = try Self.locateXQBinary()
        let (status, stdout, stderr) = try Self.run(process: xqPath, args: [".targets", "--project", projPath.string], workingDirectory: Self.packageRoot())
        if status != 0 {
            XCTFail("xq failed (\(status)): \nSTDERR: \(stderr)\nSTDOUT: \(stdout)")
            return
        }

        // Assert: parse JSON and verify target names
        struct ResultTarget: Decodable { let name: String }
        guard let data = stdout.data(using: String.Encoding.utf8) else { XCTFail("no data"); return }
        let out = try JSONDecoder().decode([ResultTarget].self, from: data)
        let names = Set(out.map { $0.name })
        XCTAssertTrue(names.contains("App"))
        XCTAssertTrue(names.contains("AppTests"))
        XCTAssertTrue(names.contains("Lib"))

        // Also verify dependencies(App) -> [Lib]
        let (status2, stdout2, stderr2) = try Self.run(process: xqPath, args: [".dependencies(\"App\")", "--project", projPath.string], workingDirectory: Self.packageRoot())
        if status2 != 0 {
            XCTFail("xq deps failed (\(status2)): \nSTDERR: \(stderr2)\nSTDOUT: \(stdout2)")
            return
        }
        struct Dep: Decodable { let name: String }
        let depData = stdout2.data(using: String.Encoding.utf8)!
        let deps = try JSONDecoder().decode([Dep].self, from: depData)
        XCTAssertEqual(Set(deps.map { $0.name }), ["Lib"])

        // pipeline: .targets[] | filter(.type == .unitTest) | dependencies(recursive: true) -> [App, Lib]
        let (status6, stdout6, stderr6) = try Self.run(process: xqPath, args: [".targets[] | filter(.type == .unitTest) | dependencies(recursive: true)", "--project", projPath.string], workingDirectory: Self.packageRoot())
        if status6 != 0 { XCTFail("xq pipeline failed (\(status6)):\nSTDERR: \(stderr6)\nSTDOUT: \(stdout6)"); return }
        let depsPipe = try JSONDecoder().decode([Dep].self, from: stdout6.data(using: .utf8)!)
        XCTAssertEqual(Set(depsPipe.map { $0.name }), ["App", "Lib"])

        // dependencies(AppTests, recursive: true) -> [App, Lib]
        let (status3, stdout3, stderr3) = try Self.run(process: xqPath, args: [".dependencies(\"AppTests\", recursive: true)", "--project", projPath.string], workingDirectory: Self.packageRoot())
        if status3 != 0 { XCTFail("xq deps recursive failed (\(status3)):\nSTDERR: \(stderr3)\nSTDOUT: \(stdout3)"); return }
        let depsRec = try JSONDecoder().decode([Dep].self, from: stdout3.data(using: .utf8)!)
        XCTAssertEqual(Set(depsRec.map { $0.name }), ["App", "Lib"])

        // dependents(Lib) -> [App]
        let (status4, stdout4, stderr4) = try Self.run(process: xqPath, args: [".dependents(\"Lib\")", "--project", projPath.string], workingDirectory: Self.packageRoot())
        if status4 != 0 { XCTFail("xq dependents failed (\(status4)):\nSTDERR: \(stderr4)\nSTDOUT: \(stdout4)"); return }
        let depsDir = try JSONDecoder().decode([Dep].self, from: stdout4.data(using: .utf8)!)
        XCTAssertEqual(Set(depsDir.map { $0.name }), ["App"])

        // dependents(Lib, recursive: true) -> [App, AppTests, AppUITests]
        let (status5, stdout5, stderr5) = try Self.run(process: xqPath, args: [".dependents(\"Lib\", recursive: true)", "--project", projPath.string], workingDirectory: Self.packageRoot())
        if status5 != 0 { XCTFail("xq dependents recursive failed (\(status5)):\nSTDERR: \(stderr5)\nSTDOUT: \(stdout5)"); return }
        let depsRec2 = try JSONDecoder().decode([Dep].self, from: stdout5.data(using: .utf8)!)
        XCTAssertEqual(Set(depsRec2.map { $0.name }), ["App", "AppTests", "AppUITests"])

        // pipeline dependents: frameworks -> dependents -> [App]
        let (status8, stdout8, stderr8) = try Self.run(process: xqPath, args: [".targets[] | filter(.type == .framework) | dependents", "--project", projPath.string], workingDirectory: Self.packageRoot())
        if status8 != 0 { XCTFail("xq pipeline dependents failed (\(status8)):\nSTDERR: \(stderr8)\nSTDOUT: \(stdout8)"); return }
        let depsPipeDeps = try JSONDecoder().decode([Dep].self, from: stdout8.data(using: .utf8)!)
        XCTAssertEqual(Set(depsPipeDeps.map { $0.name }), ["App"])

        // pipeline dependents recursive: frameworks -> dependents(recursive: true) -> [App, AppTests, AppUITests]
        let (status9, stdout9, stderr9) = try Self.run(process: xqPath, args: [".targets[] | filter(.type == .framework) | dependents(recursive: true)", "--project", projPath.string], workingDirectory: Self.packageRoot())
        if status9 != 0 { XCTFail("xq pipeline dependents recursive failed (\(status9)):\nSTDERR: \(stderr9)\nSTDOUT: \(stdout9)"); return }
        let depsPipeDepsRec = try JSONDecoder().decode([Dep].self, from: stdout9.data(using: .utf8)!)
        XCTAssertEqual(Set(depsPipeDepsRec.map { $0.name }), ["App", "AppTests", "AppUITests"])

        // reverseDependencies alias should work the same
        let (status7, stdout7, stderr7) = try Self.run(process: xqPath, args: [".reverseDependencies(\"Lib\")", "--project", projPath.string], workingDirectory: Self.packageRoot())
        if status7 != 0 { XCTFail("xq reverseDependencies failed (\(status7)):\nSTDERR: \(stderr7)\nSTDOUT: \(stdout7)"); return }
        let depsAlias = try JSONDecoder().decode([Dep].self, from: stdout7.data(using: .utf8)!)
        XCTAssertEqual(Set(depsAlias.map { $0.name }), ["App"])
    }

    // MARK: - Helpers
    private static func locateXQBinary() throws -> String {
        let root = packageRoot()
        // Try swift build --show-bin-path first
        if let (code, out, _) = try? run(process: "/usr/bin/env", args: ["swift", "build", "-c", "debug", "--show-bin-path"], workingDirectory: root), code == 0 {
            let bin = out.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = URL(fileURLWithPath: bin).appendingPathComponent("xq").path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        // Fallback to .build/debug/xq
        let fallback = URL(fileURLWithPath: root).appendingPathComponent(".build/debug/xq").path
        return fallback
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
        try proc.run()
        proc.waitUntilExit()

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (proc.terminationStatus, out, err)
    }
}

// Local test helpers (duplicated to avoid cross-file visibility issues)
private enum Temporary {
    struct TempDir { let url: URL; var path: String { url.path } }
    static func makeTempDir() throws -> TempDir {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return TempDir(url: url)
    }
}
