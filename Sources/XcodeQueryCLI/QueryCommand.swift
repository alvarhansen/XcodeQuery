import Foundation
import ArgumentParser
import XcodeQueryKit

public struct QueryCommand: AsyncParsableCommand {
    @Argument(help: "The query to execute")
    var query: String

    @Option(name: [.customShort("p"), .long], help: "Path to .xcodeproj (optional)")
    var project: String?
    
    public init() {}
    
    public func run() async throws {
        let xc = XcodeProjectQuery(projectPath: try resolveProjectPath())
        let result = try xc.evaluate(query: query)
        
        let json = try JSONEncoder().encode(result)
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
