import XCTest
import Foundation
import PathKit
import XcodeGenKit
import ProjectSpec
@testable import XcodeQueryKit

final class InteractiveModeTests: XCTestCase {
    func testXcodeProjectQuerySessionReuse() throws {
        // Arrange: small project
        let tmp = try Temporary.makeTempDir()
        let projPath = Path(tmp.path) + "Sample.xcodeproj"

        try FileManager.default.createDirectory(atPath: tmp.path + "/App/Sources", withIntermediateDirectories: true)
        try "// app".write(toFile: tmp.path + "/App/Sources/AppFile.swift", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: tmp.path + "/Lib/Sources", withIntermediateDirectories: true)
        try "// lib".write(toFile: tmp.path + "/Lib/Sources/LibFile.swift", atomically: true, encoding: .utf8)

        let project = Project(
            basePath: Path(tmp.path),
            name: "Sample",
            targets: [
                Target(name: "Lib", type: .framework, platform: .iOS, sources: [TargetSource(path: "Lib/Sources")]),
                Target(name: "App", type: .application, platform: .iOS, sources: [TargetSource(path: "App/Sources")], dependencies: [Dependency(type: .target, reference: "Lib")])
            ]
        )
        let generator = ProjectGenerator(project: project)
        let xcodeproj = try generator.generateXcodeProject(in: Path(tmp.path), userName: "CI")
        try xcodeproj.write(path: projPath)

        // Act: baseline via XcodeProjectQuery
        let oneShot = XcodeProjectQuery(projectPath: projPath.string)
        let any1 = try oneShot.evaluate(query: "targets { name type }")
        let any1Data = try JSONEncoder().encode(any1)

        // Session with reuse
        let session = try XcodeProjectQuerySession(projectPath: projPath.string)
        let anyA = try session.evaluate(query: "targets { name type }")
        let anyB = try session.evaluate(query: "targets(type: FRAMEWORK) { name }")

        // Assert: first call matches baseline
        let dataA = try JSONEncoder().encode(anyA)
        XCTAssertEqual(try JSON(data: any1Data), try JSON(data: dataA))

        // Assert: second call is valid JSON and contains only framework target
        struct T: Decodable { let name: String }
        struct R: Decodable { let targets: [T] }
        let r = try JSONDecoder().decode(R.self, from: JSONEncoder().encode(anyB))
        XCTAssertTrue(r.targets.contains { $0.name == "Lib" })
        XCTAssertFalse(r.targets.contains { $0.name == "App" })
    }

    func testInteractiveNonTTYLineByLine() throws {
        // Arrange project
        let tmp = try Temporary.makeTempDir()
        let projPath = Path(tmp.path) + "Sample.xcodeproj"
        try FileManager.default.createDirectory(atPath: tmp.path + "/App/Sources", withIntermediateDirectories: true)
        try "// app".write(toFile: tmp.path + "/App/Sources/AppFile.swift", atomically: true, encoding: .utf8)

        let project = Project(
            basePath: Path(tmp.path),
            name: "Sample",
            targets: [Target(name: "App", type: .application, platform: .iOS, sources: [TargetSource(path: "App/Sources")])]
        )
        let generator = ProjectGenerator(project: project)
        let xcodeproj = try generator.generateXcodeProject(in: Path(tmp.path), userName: "CI")
        try xcodeproj.write(path: projPath)

        let xcqPath = try Self.locateXCQBinary()
        let input = "targets { name }\n"
        let (status, stdout, stderr) = try Self.runWithInput(process: xcqPath, args: ["interactive", "--project", projPath.string], stdin: input, workingDirectory: Self.packageRoot())
        if status != 0 { XCTFail("interactive failed (\(status))\nSTDERR: \(stderr)"); return }

        // Should be pretty JSON with the 'targets' key
        struct Out: Decodable { let targets: [NameOnly] }
        struct NameOnly: Decodable { let name: String }
        let out = try JSONDecoder().decode(Out.self, from: stdout.data(using: .utf8)!)
        XCTAssertFalse(out.targets.isEmpty)
    }

    // MARK: - Helpers
    struct JSON: Equatable { let data: Data
        init(data: Data) throws {
            self.data = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: [.sortedKeys])
        }
    }
}

private extension InteractiveModeTests {
    static func locateXCQBinary() throws -> String {
        let root = packageRoot()
        if let (code, out, _) = try? runWithInput(process: "/usr/bin/env", args: ["swift", "build", "-c", "debug", "--show-bin-path"], stdin: "", workingDirectory: root), code == 0 {
            let bin = out.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = URL(fileURLWithPath: bin).appendingPathComponent("xcq").path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return URL(fileURLWithPath: packageRoot()).appendingPathComponent(".build/debug/xcq").path
    }

    static func packageRoot(file: String = #filePath) -> String {
        var url = URL(fileURLWithPath: file)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            let pkg = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: pkg.path) { return url.path }
        }
        return FileManager.default.currentDirectoryPath
    }

    @discardableResult
    static func runWithInput(process: String, args: [String], stdin: String, workingDirectory: String) throws -> (Int32, String, String) {
        let proc = Process()
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        proc.executableURL = URL(fileURLWithPath: process)
        proc.arguments = args
        let outPipe = Pipe(); proc.standardOutput = outPipe
        let errPipe = Pipe(); proc.standardError = errPipe
        let inPipe = Pipe(); proc.standardInput = inPipe
        try proc.run()
        if let data = stdin.data(using: .utf8) { inPipe.fileHandleForWriting.write(data) }
        inPipe.fileHandleForWriting.closeFile()
        proc.waitUntilExit()
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
