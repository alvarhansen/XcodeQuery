import Foundation
import ArgumentParser
import XcodeQueryKit

public struct QueryCommand: AsyncParsableCommand {
    @Argument(help: "The query to execute")
    var query: String
    
    @Argument(help: "Path to Xcode project")
    var projectPath: String
    
    public init() {}
    
    public func run() async throws {
        print("query:", query)
        print("projectPath", projectPath)
        let xc = XcodeProjectQuery(projectPath: projectPath)
        let result = try xc.evaluate(query: query)
        
        let json = try JSONEncoder().encode(result)
        print(String(data: json, encoding: .utf8) ?? "")
    }
}
