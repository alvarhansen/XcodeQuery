import Foundation
import ArgumentParser
import XcodeQueryKit

public struct QueryCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Execute a GraphQL query against an Xcode project"
    )
    @Argument(help: "GraphQL-style selection without top-level braces (e.g., targets { name type })")
    var query: String

    @Option(name: [.customShort("p"), .long], help: "Path to .xcodeproj (optional)")
    var project: String?
    
    public init() {}
    
    public func run() async throws {
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
