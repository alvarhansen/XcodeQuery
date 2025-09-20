import Foundation
import GraphQL

// Phase 1: GraphQLSwift schema definition mirroring the frozen baseline.
// Execution/resolvers are added in later phases; here we only define types/fields/args.
enum XQGraphQLSwiftSchema {
    static func makeSchema() throws -> GraphQLSchema {
        // MARK: Scalars
        let string = GraphQLString
        let boolean = GraphQLBoolean

        // MARK: Enums
        let targetType = try GraphQLEnumType(name: "TargetType", values: [
            "APP": GraphQLEnumValue(value: Map("APP")),
            "FRAMEWORK": GraphQLEnumValue(value: Map("FRAMEWORK")),
            "STATIC_LIBRARY": GraphQLEnumValue(value: Map("STATIC_LIBRARY")),
            "DYNAMIC_LIBRARY": GraphQLEnumValue(value: Map("DYNAMIC_LIBRARY")),
            "UNIT_TEST": GraphQLEnumValue(value: Map("UNIT_TEST")),
            "UI_TEST": GraphQLEnumValue(value: Map("UI_TEST")),
            "EXTENSION": GraphQLEnumValue(value: Map("EXTENSION")),
            "BUNDLE": GraphQLEnumValue(value: Map("BUNDLE")),
            "COMMAND_LINE_TOOL": GraphQLEnumValue(value: Map("COMMAND_LINE_TOOL")),
            "WATCH_APP": GraphQLEnumValue(value: Map("WATCH_APP")),
            "WATCH2_APP": GraphQLEnumValue(value: Map("WATCH2_APP")),
            "TV_APP": GraphQLEnumValue(value: Map("TV_APP")),
            "OTHER": GraphQLEnumValue(value: Map("OTHER")),
        ])
        let pathMode = try GraphQLEnumType(name: "PathMode", values: [
            "FILE_REF": GraphQLEnumValue(value: Map("FILE_REF")),
            "ABSOLUTE": GraphQLEnumValue(value: Map("ABSOLUTE")),
            "NORMALIZED": GraphQLEnumValue(value: Map("NORMALIZED")),
        ])
        let scriptStage = try GraphQLEnumType(name: "ScriptStage", values: [
            "PRE": GraphQLEnumValue(value: Map("PRE")),
            "POST": GraphQLEnumValue(value: Map("POST")),
        ])

        // MARK: Inputs
        let stringMatch = try GraphQLInputObjectType(name: "StringMatch", fields: [
            "eq": InputObjectField(type: string),
            "regex": InputObjectField(type: string),
            "prefix": InputObjectField(type: string),
            "suffix": InputObjectField(type: string),
            "contains": InputObjectField(type: string),
        ])
        let targetFilter = try GraphQLInputObjectType(name: "TargetFilter", fields: [
            "name": InputObjectField(type: stringMatch),
            "type": InputObjectField(type: targetType),
        ])
        let sourceFilter = try GraphQLInputObjectType(name: "SourceFilter", fields: [
            "path": InputObjectField(type: stringMatch),
            "target": InputObjectField(type: stringMatch),
        ])
        let resourceFilter = try GraphQLInputObjectType(name: "ResourceFilter", fields: [
            "path": InputObjectField(type: stringMatch),
            "target": InputObjectField(type: stringMatch),
        ])
        let buildScriptFilter = try GraphQLInputObjectType(name: "BuildScriptFilter", fields: [
            "stage": InputObjectField(type: scriptStage),
            "name": InputObjectField(type: stringMatch),
            "target": InputObjectField(type: stringMatch),
        ])

        // MARK: Objects
        // Leaf/simple types
        let source = try GraphQLObjectType(name: "Source", fields: [
            "path": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveSource_path)
        ])
        let resource = try GraphQLObjectType(name: "Resource", fields: [
            "path": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveResource_path)
        ])
        let buildScript = try GraphQLObjectType(name: "BuildScript", fields: [
            "name": GraphQLField(type: string, resolve: XQResolvers.resolveBuildScript_name),
            "stage": GraphQLField(type: GraphQLNonNull(scriptStage), resolve: XQResolvers.resolveBuildScript_stage),
            "inputPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))), resolve: XQResolvers.resolveBuildScript_inputPaths),
            "outputPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))), resolve: XQResolvers.resolveBuildScript_outputPaths),
            "inputFileListPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))), resolve: XQResolvers.resolveBuildScript_inputFileListPaths),
            "outputFileListPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))), resolve: XQResolvers.resolveBuildScript_outputFileListPaths),
        ])

        // Target and nested fields
        let target = try GraphQLObjectType(name: "Target", fields: [
            "name": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveTarget_name),
            "type": GraphQLField(type: GraphQLNonNull(targetType), resolve: XQResolvers.resolveTarget_type),
            "dependencies": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull("Target"))),
                args: [
                    "recursive": GraphQLArgument(type: boolean, defaultValue: Map(false)),
                    "filter": GraphQLArgument(type: targetFilter)
                ]
            , resolve: XQResolvers.resolveTarget_dependencies),
            "sources": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(source))),
                args: [
                    "pathMode": GraphQLArgument(type: pathMode, defaultValue: Map("FILE_REF")),
                    "filter": GraphQLArgument(type: sourceFilter)
                ]
            , resolve: XQResolvers.resolveTarget_sources),
            "resources": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(resource))),
                args: [
                    "pathMode": GraphQLArgument(type: pathMode, defaultValue: Map("FILE_REF")),
                    "filter": GraphQLArgument(type: resourceFilter)
                ]
            , resolve: XQResolvers.resolveTarget_resources),
            "buildScripts": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(buildScript))),
                args: ["filter": GraphQLArgument(type: buildScriptFilter)],
                resolve: XQResolvers.resolveTarget_buildScripts
            ),
        ])

        let targetSource = try GraphQLObjectType(name: "TargetSource", fields: [
            "target": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveFlatSource_target),
            "path": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveFlatSource_path)
        ])
        let targetResource = try GraphQLObjectType(name: "TargetResource", fields: [
            "target": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveFlatResource_target),
            "path": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveFlatResource_path)
        ])
        let targetDependency = try GraphQLObjectType(name: "TargetDependency", fields: [
            "target": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveFlatDependency_target),
            "name": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveFlatDependency_name),
            "type": GraphQLField(type: GraphQLNonNull(targetType), resolve: XQResolvers.resolveFlatDependency_type)
        ])
        let targetBuildScript = try GraphQLObjectType(name: "TargetBuildScript", fields: [
            "target": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveFlatBuildScript_target),
            "name": GraphQLField(type: string, resolve: XQResolvers.resolveFlatBuildScript_name),
            "stage": GraphQLField(type: GraphQLNonNull(scriptStage), resolve: XQResolvers.resolveFlatBuildScript_stage),
            "inputPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))), resolve: XQResolvers.resolveFlatBuildScript_inputPaths),
            "outputPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))), resolve: XQResolvers.resolveFlatBuildScript_outputPaths),
            "inputFileListPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))), resolve: XQResolvers.resolveFlatBuildScript_inputFileListPaths),
            "outputFileListPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))), resolve: XQResolvers.resolveFlatBuildScript_outputFileListPaths),
        ])
        let targetMembership = try GraphQLObjectType(name: "TargetMembership", fields: [
            "path": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveMembership_path),
            "targets": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))), resolve: XQResolvers.resolveMembership_targets)
        ])

        // Build settings: inputs and objects
        let projectBuildSettingFilter = try GraphQLInputObjectType(name: "ProjectBuildSettingFilter", fields: [
            "key": InputObjectField(type: stringMatch),
            "configuration": InputObjectField(type: stringMatch),
        ])
        let projectBuildSetting = try GraphQLObjectType(name: "ProjectBuildSetting", fields: [
            "configuration": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveProjectBuildSetting_configuration),
            "key": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveProjectBuildSetting_key),
            "value": GraphQLField(type: string, resolve: XQResolvers.resolveProjectBuildSetting_value),
            "values": GraphQLField(type: GraphQLList(GraphQLNonNull(string)), resolve: XQResolvers.resolveProjectBuildSetting_values),
            "isArray": GraphQLField(type: GraphQLNonNull(boolean), resolve: XQResolvers.resolveProjectBuildSetting_isArray),
        ])

        // MARK: Query root
        let query = try GraphQLObjectType(name: "Query", fields: [
            "buildConfigurations": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))),
                resolve: XQResolvers.resolveBuildConfigurations
            ),
            "projectBuildSettings": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(projectBuildSetting))),
                args: [
                    "filter": GraphQLArgument(type: projectBuildSettingFilter)
                ],
                resolve: XQResolvers.resolveProjectBuildSettings
            ),
            "targets": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(target))),
                args: [
                    "type": GraphQLArgument(type: targetType),
                    "filter": GraphQLArgument(type: targetFilter)
                ],
                resolve: XQResolvers.resolveTargets
            ),
            "target": GraphQLField(
                type: target,
                args: ["name": GraphQLArgument(type: GraphQLNonNull(string))],
                resolve: XQResolvers.resolveTarget
            ),
            "dependencies": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(target))),
                args: [
                    "name": GraphQLArgument(type: GraphQLNonNull(string)),
                    "recursive": GraphQLArgument(type: boolean, defaultValue: Map(false)),
                    "filter": GraphQLArgument(type: targetFilter)
                ],
                resolve: XQResolvers.resolveDependenciesTop(reverse: false)
            ),
            "dependents": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(target))),
                args: [
                    "name": GraphQLArgument(type: GraphQLNonNull(string)),
                    "recursive": GraphQLArgument(type: boolean, defaultValue: Map(false)),
                    "filter": GraphQLArgument(type: targetFilter)
                ],
                resolve: XQResolvers.resolveDependenciesTop(reverse: true)
            ),
            "targetSources": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(targetSource))),
                args: [
                    "pathMode": GraphQLArgument(type: pathMode, defaultValue: Map("FILE_REF")),
                    "filter": GraphQLArgument(type: sourceFilter)
                ],
                resolve: XQResolvers.resolveTargetSources
            ),
            "targetResources": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(targetResource))),
                args: [
                    "pathMode": GraphQLArgument(type: pathMode, defaultValue: Map("FILE_REF")),
                    "filter": GraphQLArgument(type: resourceFilter)
                ],
                resolve: XQResolvers.resolveTargetResources
            ),
            "targetDependencies": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(targetDependency))),
                args: [
                    "recursive": GraphQLArgument(type: boolean, defaultValue: Map(false)),
                    "filter": GraphQLArgument(type: targetFilter)
                ],
                resolve: XQResolvers.resolveTargetDependencies
            ),
            "targetBuildScripts": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(targetBuildScript))),
                args: ["filter": GraphQLArgument(type: buildScriptFilter)],
                resolve: XQResolvers.resolveTargetBuildScripts
            ),
            "targetMembership": GraphQLField(
                type: GraphQLNonNull(targetMembership),
                args: [
                    "path": GraphQLArgument(type: GraphQLNonNull(string)),
                    "pathMode": GraphQLArgument(type: pathMode, defaultValue: Map("FILE_REF"))
                ],
                resolve: XQResolvers.resolveTargetMembership
            ),
        ])

        return try GraphQLSchema(query: query)
    }
}
