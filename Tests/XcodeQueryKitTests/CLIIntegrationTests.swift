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
                Target(name: "App", type: .application, platform: .iOS),
                Target(name: "AppTests", type: .unitTestBundle, platform: .iOS),
                Target(name: "Lib", type: .framework, platform: .iOS),
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
