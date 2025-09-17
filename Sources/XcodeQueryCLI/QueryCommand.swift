import Foundation
import ArgumentParser
import XcodeQueryKit
import Darwin

public struct QueryCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Execute a GraphQL query against an Xcode project"
    )
    @Argument(help: "GraphQL-style selection without top-level braces (e.g., targets { name type })")
    var query: String

    @Option(name: [.customShort("p"), .long], help: "Path to .xcodeproj (optional)")
    var project: String?

    @Flag(name: .customLong("legacy"), help: "Use legacy parser engine instead of GraphQLSwift (temporary fallback)")
    var legacy: Bool = false

    @Flag(name: .customLong("compare-engines"), help: ArgumentHelp("Execute both engines and report mismatches (stderr)", visibility: .hidden))
    var compareEngines: Bool = false
    
    public init() {}
    
    public func run() async throws {
        // Default the CLI to GraphQLSwift; allow fallback via --legacy
        if legacy {
            setenv("XCQ_USE_LEGACY", "1", 1)
        } else {
            setenv("XCQ_USE_GRAPHQLSWIFT", "1", 1)
        }
        if compareEngines { setenv("XCQ_COMPARE_ENGINES", "1", 1) }

        let xc = XcodeProjectQuery(projectPath: try resolveProjectPath())
        let result = try xc.evaluate(query: query)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let json = try encoder.encode(result)
        print(String(data: json, encoding: .utf8) ?? "")
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
