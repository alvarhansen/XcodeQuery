import Foundation
import ArgumentParser
import XcodeQueryKit
import Darwin

public struct InteractiveCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "interactive",
        abstract: "Start interactive query mode (pretty JSON preview)"
    )

    @Option(name: [.customShort("p"), .long], help: "Path to .xcodeproj (optional)")
    var project: String?

    @Option(name: .long, help: "Debounce delay in milliseconds (default: 200)")
    var debounce: Int = 200

    @Flag(name: .customLong("no-color"), help: "Disable ANSI colors in interactive UI (errors/hints)")
    var noColor: Bool = false
    @Flag(name: .customLong("color"), help: "Force ANSI colors in interactive UI (errors/hints)")
    var yesColor: Bool = false

    public init() {}

    public func run() async throws {
        let projectPath = try resolveProjectPath()
        let session = try XcodeProjectQuerySession(projectPath: projectPath)

        let env = ProcessInfo.processInfo.environment
        let force = env["XCQ_FORCE_COLOR"] == "1" || env["FORCE_COLOR"] == "1"
        let enableColor = noColor ? false : (yesColor || force || (isatty(STDOUT_FILENO) == 1))

        let isTTY = (isatty(STDIN_FILENO) == 1) && (isatty(STDOUT_FILENO) == 1)
        if isTTY {
            let engine = InteractiveSession(core: session, debounceMs: max(0, debounce), colorEnabled: enableColor)
            try await engine.start()
        } else {
            try runNonTTY(core: session)
        }
    }

    private func runNonTTY(core: XcodeProjectQuerySession) throws {
        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            do {
                let any = try core.evaluate(query: trimmed)
                let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
                let data = try enc.encode(any)
                if let s = String(data: data, encoding: .utf8) { print(s) }
            } catch {
                let msg = String(describing: error)
                FileHandle.standardError.write(("Error: \(msg)\n").data(using: .utf8)!)
            }
        }
    }

    private func resolveProjectPath() throws -> String {
        if let project { return project }
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        let items = try fm.contentsOfDirectory(atPath: cwd)
        if let xcodeproj = items.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return cwd + "/" + xcodeproj
        }
        throw ValidationError("No .xcodeproj found in current directory. Pass with --project.")
    }
}
