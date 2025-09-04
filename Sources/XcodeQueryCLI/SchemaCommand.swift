import Foundation
import ArgumentParser

public struct SchemaCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Print the GraphQL-style query schema summary"
    )

    public init() {}

    public func run() async throws {
        print(Self.schemaText)
    }

    private static let schemaText: String = {
        return """
        XcodeQuery GraphQL Schema (summary)

        Top-level fields (selection required):
        - targets(type: TargetType, filter: TargetFilter): [Target!]!
        - target(name: String!): Target
        - dependencies(name: String!, recursive: Boolean = false, filter: TargetFilter): [Target!]!
        - dependents(name: String!, recursive: Boolean = false, filter: TargetFilter): [Target!]!
        - targetSources(pathMode: PathMode = FILE_REF, filter: SourceFilter): [TargetSource!]!
        - targetResources(pathMode: PathMode = FILE_REF, filter: ResourceFilter): [TargetResource!]!
        - targetDependencies(recursive: Boolean = false, filter: TargetFilter): [TargetDependency!]!
        - targetBuildScripts(filter: BuildScriptFilter): [TargetBuildScript!]!
        - targetMembership(path: String!, pathMode: PathMode = FILE_REF): TargetMembership!

        Types:
        - type Target {
            name: String!
            type: TargetType!
            dependencies(recursive: Boolean = false, filter: TargetFilter): [Target!]!
            sources(pathMode: PathMode = FILE_REF, filter: SourceFilter): [Source!]!
            resources(pathMode: PathMode = FILE_REF, filter: ResourceFilter): [Resource!]!
            buildScripts(filter: BuildScriptFilter): [BuildScript!]!
          }
        - type Source { path: String! }
        - type Resource { path: String! }
        - type BuildScript {
            name: String
            stage: ScriptStage!
            inputPaths: [String!]!
            outputPaths: [String!]!
            inputFileListPaths: [String!]!
            outputFileListPaths: [String!]!
          }
        - type TargetSource { target: String!, path: String! }
        - type TargetResource { target: String!, path: String! }
        - type TargetDependency { target: String!, name: String!, type: TargetType! }
        - type TargetBuildScript { target: String!, name: String, stage: ScriptStage!, inputPaths: [String!]!, outputPaths: [String!]!, inputFileListPaths: [String!]!, outputFileListPaths: [String!]! }
        - type TargetMembership { path: String!, targets: [String!]! }

        Enums:
        - enum TargetType { APP, FRAMEWORK, STATIC_LIBRARY, DYNAMIC_LIBRARY, UNIT_TEST, UI_TEST, EXTENSION, BUNDLE, COMMAND_LINE_TOOL, WATCH_APP, WATCH2_APP, TV_APP, OTHER }
        - enum PathMode { FILE_REF, ABSOLUTE, NORMALIZED }
        - enum ScriptStage { PRE, POST }

        Filters:
        - input StringMatch { eq: String, regex: String, prefix: String, suffix: String, contains: String }
        - input TargetFilter { name: StringMatch, type: TargetType }
        - input SourceFilter { path: StringMatch, target: StringMatch }
        - input ResourceFilter { path: StringMatch, target: StringMatch }
        - input BuildScriptFilter { stage: ScriptStage, name: StringMatch, target: StringMatch }

        Examples:
        - { targets { name type } }
        - { dependencies(name: \"App\") { name } }
        - { targets(type: UNIT_TEST) { dependencies(recursive: true) { name } } }
        - { targetSources(pathMode: NORMALIZED) { target path } }
        - { targetMembership(path: \"Shared/Shared.swift\", pathMode: NORMALIZED) { path targets } }
        - { targetBuildScripts(filter: { stage: PRE }) { target name stage } }
        """
    }()
}
