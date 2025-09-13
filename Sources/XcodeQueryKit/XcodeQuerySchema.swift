import Foundation

public indirect enum XQSTypeRef: Equatable, Sendable {
    case named(String, nonNull: Bool = false)
    case list(of: XQSTypeRef, nonNull: Bool = false, elementNonNull: Bool = false)

    public static func nn(_ name: String) -> XQSTypeRef { .named(name, nonNull: true) }
    public static func listNN(_ name: String) -> XQSTypeRef { .list(of: .named(name), nonNull: true, elementNonNull: true) }
}

public struct XQArgument: Equatable, Sendable {
    public var name: String
    public var type: XQSTypeRef
    public var defaultValue: String?
    public init(_ name: String, _ type: XQSTypeRef, defaultValue: String? = nil) { self.name = name; self.type = type; self.defaultValue = defaultValue }
}

public struct XQField: Equatable, Sendable {
    public var name: String
    public var args: [XQArgument]
    public var type: XQSTypeRef
    public init(_ name: String, args: [XQArgument] = [], type: XQSTypeRef) { self.name = name; self.args = args; self.type = type }
}

public struct XQObjectType: Equatable, Sendable {
    public var name: String
    public var fields: [XQField]
    public init(_ name: String, fields: [XQField]) { self.name = name; self.fields = fields }
}

public struct XQEnumType: Equatable, Sendable {
    public var name: String
    public var cases: [String]
    public init(_ name: String, cases: [String]) { self.name = name; self.cases = cases }
}

public struct XQInputObjectType: Equatable, Sendable {
    public var name: String
    public var fields: [XQArgument]
    public init(_ name: String, fields: [XQArgument]) { self.name = name; self.fields = fields }
}

public struct XQSchema: Equatable, Sendable {
    public var topLevel: [XQField]
    public var types: [XQObjectType]
    public var enums: [XQEnumType]
    public var inputs: [XQInputObjectType]
}

public enum XcodeQuerySchema {
    public static let schema: XQSchema = {
        // Enums
        let targetType = XQEnumType("TargetType", cases: [
            "APP", "FRAMEWORK", "STATIC_LIBRARY", "DYNAMIC_LIBRARY", "UNIT_TEST", "UI_TEST", "EXTENSION", "BUNDLE", "COMMAND_LINE_TOOL", "WATCH_APP", "WATCH2_APP", "TV_APP", "OTHER"
        ])
        let pathMode = XQEnumType("PathMode", cases: ["FILE_REF", "ABSOLUTE", "NORMALIZED"])
        let scriptStage = XQEnumType("ScriptStage", cases: ["PRE", "POST"])

        // Inputs
        let stringMatch = XQInputObjectType("StringMatch", fields: [
            XQArgument("eq", .named("String")),
            XQArgument("regex", .named("String")),
            XQArgument("prefix", .named("String")),
            XQArgument("suffix", .named("String")),
            XQArgument("contains", .named("String"))
        ])
        let targetFilter = XQInputObjectType("TargetFilter", fields: [
            XQArgument("name", .named("StringMatch")),
            XQArgument("type", .named("TargetType"))
        ])
        let sourceFilter = XQInputObjectType("SourceFilter", fields: [
            XQArgument("path", .named("StringMatch")),
            XQArgument("target", .named("StringMatch"))
        ])
        let resourceFilter = XQInputObjectType("ResourceFilter", fields: [
            XQArgument("path", .named("StringMatch")),
            XQArgument("target", .named("StringMatch"))
        ])
        let buildScriptFilter = XQInputObjectType("BuildScriptFilter", fields: [
            XQArgument("stage", .named("ScriptStage")),
            XQArgument("name", .named("StringMatch")),
            XQArgument("target", .named("StringMatch"))
        ])

        // Object types
        let target = XQObjectType("Target", fields: [
            XQField("name", type: .nn("String")),
            XQField("type", type: .nn("TargetType")),
            XQField("dependencies", args: [XQArgument("recursive", .named("Boolean"), defaultValue: "false"), XQArgument("filter", .named("TargetFilter"))], type: .listNN("Target")),
            XQField("sources", args: [XQArgument("pathMode", .named("PathMode"), defaultValue: "FILE_REF"), XQArgument("filter", .named("SourceFilter"))], type: .listNN("Source")),
            XQField("resources", args: [XQArgument("pathMode", .named("PathMode"), defaultValue: "FILE_REF"), XQArgument("filter", .named("ResourceFilter"))], type: .listNN("Resource")),
            XQField("buildScripts", args: [XQArgument("filter", .named("BuildScriptFilter"))], type: .listNN("BuildScript"))
        ])
        let source = XQObjectType("Source", fields: [XQField("path", type: .nn("String"))])
        let resource = XQObjectType("Resource", fields: [XQField("path", type: .nn("String"))])
        let buildScript = XQObjectType("BuildScript", fields: [
            XQField("name", type: .named("String")),
            XQField("stage", type: .nn("ScriptStage")),
            XQField("inputPaths", type: .list(of: .nn("String"), nonNull: true, elementNonNull: true)),
            XQField("outputPaths", type: .list(of: .nn("String"), nonNull: true, elementNonNull: true)),
            XQField("inputFileListPaths", type: .list(of: .nn("String"), nonNull: true, elementNonNull: true)),
            XQField("outputFileListPaths", type: .list(of: .nn("String"), nonNull: true, elementNonNull: true))
        ])

        // Flat view types
        let targetSource = XQObjectType("TargetSource", fields: [XQField("target", type: .nn("String")), XQField("path", type: .nn("String"))])
        let targetResource = XQObjectType("TargetResource", fields: [XQField("target", type: .nn("String")), XQField("path", type: .nn("String"))])
        let targetDependency = XQObjectType("TargetDependency", fields: [XQField("target", type: .nn("String")), XQField("name", type: .nn("String")), XQField("type", type: .nn("TargetType"))])
        let targetBuildScript = XQObjectType("TargetBuildScript", fields: [
            XQField("target", type: .nn("String")),
            XQField("name", type: .named("String")),
            XQField("stage", type: .nn("ScriptStage")),
            XQField("inputPaths", type: .list(of: .nn("String"), nonNull: true, elementNonNull: true)),
            XQField("outputPaths", type: .list(of: .nn("String"), nonNull: true, elementNonNull: true)),
            XQField("inputFileListPaths", type: .list(of: .nn("String"), nonNull: true, elementNonNull: true)),
            XQField("outputFileListPaths", type: .list(of: .nn("String"), nonNull: true, elementNonNull: true))
        ])
        let targetMembership = XQObjectType("TargetMembership", fields: [
            XQField("path", type: .nn("String")),
            XQField("targets", type: .list(of: .nn("String"), nonNull: true, elementNonNull: true))
        ])

        // Top-level fields
        let top: [XQField] = [
            XQField("targets", args: [XQArgument("type", .named("TargetType")), XQArgument("filter", .named("TargetFilter"))], type: .listNN("Target")),
            XQField("target", args: [XQArgument("name", .nn("String"))], type: .named("Target")),
            XQField("dependencies", args: [XQArgument("name", .nn("String")), XQArgument("recursive", .named("Boolean"), defaultValue: "false"), XQArgument("filter", .named("TargetFilter"))], type: .listNN("Target")),
            XQField("dependents", args: [XQArgument("name", .nn("String")), XQArgument("recursive", .named("Boolean"), defaultValue: "false"), XQArgument("filter", .named("TargetFilter"))], type: .listNN("Target")),
            XQField("targetSources", args: [XQArgument("pathMode", .named("PathMode"), defaultValue: "FILE_REF"), XQArgument("filter", .named("SourceFilter"))], type: .listNN("TargetSource")),
            XQField("targetResources", args: [XQArgument("pathMode", .named("PathMode"), defaultValue: "FILE_REF"), XQArgument("filter", .named("ResourceFilter"))], type: .listNN("TargetResource")),
            XQField("targetDependencies", args: [XQArgument("recursive", .named("Boolean"), defaultValue: "false"), XQArgument("filter", .named("TargetFilter"))], type: .listNN("TargetDependency")),
            XQField("targetBuildScripts", args: [XQArgument("filter", .named("BuildScriptFilter"))], type: .listNN("TargetBuildScript")),
            XQField("targetMembership", args: [XQArgument("path", .nn("String")), XQArgument("pathMode", .named("PathMode"), defaultValue: "FILE_REF")], type: .nn("TargetMembership"))
        ]

        return XQSchema(
            topLevel: top,
            types: [target, source, resource, buildScript, targetSource, targetResource, targetDependency, targetBuildScript, targetMembership],
            enums: [targetType, pathMode, scriptStage],
            inputs: [stringMatch, targetFilter, sourceFilter, resourceFilter, buildScriptFilter]
        )
    }()
}
