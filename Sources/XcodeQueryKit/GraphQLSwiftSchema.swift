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
            "path": GraphQLField(type: GraphQLNonNull(string))
        ])
        let resource = try GraphQLObjectType(name: "Resource", fields: [
            "path": GraphQLField(type: GraphQLNonNull(string))
        ])
        let buildScript = try GraphQLObjectType(name: "BuildScript", fields: [
            "name": GraphQLField(type: string),
            "stage": GraphQLField(type: GraphQLNonNull(scriptStage)),
            "inputPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string)))),
            "outputPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string)))),
            "inputFileListPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string)))),
            "outputFileListPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string)))),
        ])

        // Target and nested fields
        let target = try GraphQLObjectType(name: "Target", fields: [
            "name": GraphQLField(type: GraphQLNonNull(string)),
            "type": GraphQLField(type: GraphQLNonNull(targetType)),
            "dependencies": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull("Target"))),
                args: [
                    "recursive": GraphQLArgument(type: boolean, defaultValue: Map(false)),
                    "filter": GraphQLArgument(type: targetFilter)
                ]
            ),
            "sources": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(source))),
                args: [
                    "pathMode": GraphQLArgument(type: pathMode, defaultValue: Map("FILE_REF")),
                    "filter": GraphQLArgument(type: sourceFilter)
                ]
            ),
            "resources": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(resource))),
                args: [
                    "pathMode": GraphQLArgument(type: pathMode, defaultValue: Map("FILE_REF")),
                    "filter": GraphQLArgument(type: resourceFilter)
                ]
            ),
            "buildScripts": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(buildScript))),
                args: ["filter": GraphQLArgument(type: buildScriptFilter)]
            ),
        ])

        let targetSource = try GraphQLObjectType(name: "TargetSource", fields: [
            "target": GraphQLField(type: GraphQLNonNull(string)),
            "path": GraphQLField(type: GraphQLNonNull(string))
        ])
        let targetResource = try GraphQLObjectType(name: "TargetResource", fields: [
            "target": GraphQLField(type: GraphQLNonNull(string)),
            "path": GraphQLField(type: GraphQLNonNull(string))
        ])
        let targetDependency = try GraphQLObjectType(name: "TargetDependency", fields: [
            "target": GraphQLField(type: GraphQLNonNull(string)),
            "name": GraphQLField(type: GraphQLNonNull(string)),
            "type": GraphQLField(type: GraphQLNonNull(targetType))
        ])
        let targetBuildScript = try GraphQLObjectType(name: "TargetBuildScript", fields: [
            "target": GraphQLField(type: GraphQLNonNull(string)),
            "name": GraphQLField(type: string),
            "stage": GraphQLField(type: GraphQLNonNull(scriptStage)),
            "inputPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string)))),
            "outputPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string)))),
            "inputFileListPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string)))),
            "outputFileListPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string)))),
        ])
        let targetMembership = try GraphQLObjectType(name: "TargetMembership", fields: [
            "path": GraphQLField(type: GraphQLNonNull(string)),
            "targets": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))))
        ])

        // MARK: Query root
        let query = try GraphQLObjectType(name: "Query", fields: [
            "targets": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(target))),
                args: [
                    "type": GraphQLArgument(type: targetType),
                    "filter": GraphQLArgument(type: targetFilter)
                ]
            ),
            "target": GraphQLField(
                type: target,
                args: ["name": GraphQLArgument(type: GraphQLNonNull(string))]
            ),
            "dependencies": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(target))),
                args: [
                    "name": GraphQLArgument(type: GraphQLNonNull(string)),
                    "recursive": GraphQLArgument(type: boolean, defaultValue: Map(false)),
                    "filter": GraphQLArgument(type: targetFilter)
                ]
            ),
            "dependents": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(target))),
                args: [
                    "name": GraphQLArgument(type: GraphQLNonNull(string)),
                    "recursive": GraphQLArgument(type: boolean, defaultValue: Map(false)),
                    "filter": GraphQLArgument(type: targetFilter)
                ]
            ),
            "targetSources": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(targetSource))),
                args: [
                    "pathMode": GraphQLArgument(type: pathMode, defaultValue: Map("FILE_REF")),
                    "filter": GraphQLArgument(type: sourceFilter)
                ]
            ),
            "targetResources": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(targetResource))),
                args: [
                    "pathMode": GraphQLArgument(type: pathMode, defaultValue: Map("FILE_REF")),
                    "filter": GraphQLArgument(type: resourceFilter)
                ]
            ),
            "targetDependencies": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(targetDependency))),
                args: [
                    "recursive": GraphQLArgument(type: boolean, defaultValue: Map(false)),
                    "filter": GraphQLArgument(type: targetFilter)
                ]
            ),
            "targetBuildScripts": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(targetBuildScript))),
                args: ["filter": GraphQLArgument(type: buildScriptFilter)]
            ),
            "targetMembership": GraphQLField(
                type: GraphQLNonNull(targetMembership),
                args: [
                    "path": GraphQLArgument(type: GraphQLNonNull(string)),
                    "pathMode": GraphQLArgument(type: pathMode, defaultValue: Map("FILE_REF"))
                ]
            ),
        ])

        return try GraphQLSchema(query: query)
    }
}
