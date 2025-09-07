import XCTest
@testable import XcodeQueryCLI

final class SchemaColorTests: XCTestCase {
    func testSchemaColorizedOutput() throws {
        // Use shell and cat -v to normalize ANSI for assertion
        let bin = try locateXCQBinary()
        _ = bin // ensure build
        // Use internal renderer to compare colored vs plain
        let colored = SchemaCommand.__test_renderSchema(useColor: true)
        let plain = SchemaCommand.__test_renderSchema(useColor: false)
        XCTAssertNotEqual(colored, plain)
        XCTAssertTrue(colored.contains("Top-level fields"))
        XCTAssertTrue(colored.contains("Types:"))
    }

    private func locateXCQBinary(file: String = #filePath) throws -> String {
        var url = URL(fileURLWithPath: file)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            let pkg = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: pkg.path) {
                if let (code, out, _) = try? run(process: "/usr/bin/env", args: ["swift", "build", "-c", "debug", "--show-bin-path"]), code == 0 {
                    let bin = out.trimmingCharacters(in: .whitespacesAndNewlines)
                    let candidate = URL(fileURLWithPath: bin).appendingPathComponent("xcq").path
                    if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
                }
                return url.appendingPathComponent(".build/debug/xcq").path
            }
        }
        return ".build/debug/xcq"
    }

    @discardableResult
    private func run(process: String, args: [String], env: [String: String] = [:], cwd: String = FileManager.default.currentDirectoryPath) throws -> (Int32, String, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: process)
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err
        try p.run(); p.waitUntilExit()
        let so = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let se = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (p.terminationStatus, so, se)
    }
}
