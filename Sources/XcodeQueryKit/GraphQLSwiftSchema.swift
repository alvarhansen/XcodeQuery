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
        // Linker dependencies enums
        let linkKind = try GraphQLEnumType(name: "LinkKind", values: [
            "FRAMEWORK": GraphQLEnumValue(value: Map("FRAMEWORK")),
            "LIBRARY": GraphQLEnumValue(value: Map("LIBRARY")),
            "SDK_FRAMEWORK": GraphQLEnumValue(value: Map("SDK_FRAMEWORK")),
            "SDK_LIBRARY": GraphQLEnumValue(value: Map("SDK_LIBRARY")),
            "PACKAGE_PRODUCT": GraphQLEnumValue(value: Map("PACKAGE_PRODUCT")),
            "OTHER": GraphQLEnumValue(value: Map("OTHER")),
        ])
        // Build settings enums
        let buildSettingsScope = try GraphQLEnumType(name: "BuildSettingsScope", values: [
            "PROJECT_ONLY": GraphQLEnumValue(value: Map("PROJECT_ONLY")),
            "TARGET_ONLY": GraphQLEnumValue(value: Map("TARGET_ONLY")),
            "MERGED": GraphQLEnumValue(value: Map("MERGED")),
        ])
        let buildSettingOrigin = try GraphQLEnumType(name: "BuildSettingOrigin", values: [
            "PROJECT": GraphQLEnumValue(value: Map("PROJECT")),
            "TARGET": GraphQLEnumValue(value: Map("TARGET")),
        ])
        // Swift Packages enums
        let requirementKind = try GraphQLEnumType(name: "RequirementKind", values: [
            "EXACT": GraphQLEnumValue(value: Map("EXACT")),
            "RANGE": GraphQLEnumValue(value: Map("RANGE")),
            "UP_TO_NEXT_MAJOR": GraphQLEnumValue(value: Map("UP_TO_NEXT_MAJOR")),
            "UP_TO_NEXT_MINOR": GraphQLEnumValue(value: Map("UP_TO_NEXT_MINOR")),
            "BRANCH": GraphQLEnumValue(value: Map("BRANCH")),
            "REVISION": GraphQLEnumValue(value: Map("REVISION")),
        ])
        let packageProductType = try GraphQLEnumType(name: "PackageProductType", values: [
            "LIBRARY": GraphQLEnumValue(value: Map("LIBRARY")),
            "EXECUTABLE": GraphQLEnumValue(value: Map("EXECUTABLE")),
            "PLUGIN": GraphQLEnumValue(value: Map("PLUGIN")),
            "OTHER": GraphQLEnumValue(value: Map("OTHER")),
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
        // Link dependencies filter
        let linkFilter = try GraphQLInputObjectType(name: "LinkFilter", fields: [
            "name": InputObjectField(type: stringMatch),
            "kind": InputObjectField(type: linkKind),
            "target": InputObjectField(type: stringMatch),
        ])
        // Build settings filter (used by Target.buildSettings and targetBuildSettings)
        let buildSettingFilter = try GraphQLInputObjectType(name: "BuildSettingFilter", fields: [
            "key": InputObjectField(type: stringMatch),
            "configuration": InputObjectField(type: stringMatch),
            "target": InputObjectField(type: stringMatch),
        ])
        // Swift Packages filters
        let swiftPackageFilter = try GraphQLInputObjectType(name: "SwiftPackageFilter", fields: [
            "name": InputObjectField(type: stringMatch),
            "identity": InputObjectField(type: stringMatch),
            "url": InputObjectField(type: stringMatch),
            "product": InputObjectField(type: stringMatch),
            "consumerTarget": InputObjectField(type: stringMatch),
        ])
        let packageProductFilter = try GraphQLInputObjectType(name: "PackageProductFilter", fields: [
            "name": InputObjectField(type: stringMatch),
        ])
        let packageProductUsageFilter = try GraphQLInputObjectType(name: "PackageProductUsageFilter", fields: [
            "target": InputObjectField(type: stringMatch),
            "package": InputObjectField(type: stringMatch),
            "product": InputObjectField(type: stringMatch),
        ])

        // MARK: Objects
        // Leaf/simple types
        let source = try GraphQLObjectType(name: "Source", fields: [
            "path": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveSource_path)
        ])
        let resource = try GraphQLObjectType(name: "Resource", fields: [
            "path": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveResource_path)
        ])
        let linkDependency = try GraphQLObjectType(name: "LinkDependency", fields: [
            "name": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveLinkDependency_name),
            "kind": GraphQLField(type: GraphQLNonNull(linkKind), resolve: XQResolvers.resolveLinkDependency_kind),
            "path": GraphQLField(type: string, resolve: XQResolvers.resolveLinkDependency_path),
            "embed": GraphQLField(type: GraphQLNonNull(boolean), resolve: XQResolvers.resolveLinkDependency_embed),
            "weak": GraphQLField(type: GraphQLNonNull(boolean), resolve: XQResolvers.resolveLinkDependency_weak),
        ])
        let buildScript = try GraphQLObjectType(name: "BuildScript", fields: [
            "name": GraphQLField(type: string, resolve: XQResolvers.resolveBuildScript_name),
            "stage": GraphQLField(type: GraphQLNonNull(scriptStage), resolve: XQResolvers.resolveBuildScript_stage),
            "inputPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))), resolve: XQResolvers.resolveBuildScript_inputPaths),
            "outputPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))), resolve: XQResolvers.resolveBuildScript_outputPaths),
            "inputFileListPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))), resolve: XQResolvers.resolveBuildScript_inputFileListPaths),
            "outputFileListPaths": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(string))), resolve: XQResolvers.resolveBuildScript_outputFileListPaths),
        ])

        // Swift Packages: objects
        let packageRequirement = try GraphQLObjectType(name: "PackageRequirement", fields: [
            "kind": GraphQLField(type: GraphQLNonNull(requirementKind), resolve: XQResolvers.resolvePackageRequirement_kind),
            "value": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolvePackageRequirement_value),
        ])
        let packageProduct = try GraphQLObjectType(name: "PackageProduct", fields: [
            "name": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolvePackageProduct_name),
            "type": GraphQLField(type: GraphQLNonNull(packageProductType), resolve: XQResolvers.resolvePackageProduct_type),
        ])
        let packageConsumer = try GraphQLObjectType(name: "PackageConsumer", fields: [
            "target": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolvePackageConsumer_target),
            "product": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolvePackageConsumer_product),
        ])
        let packageProductUsage = try GraphQLObjectType(name: "PackageProductUsage", fields: [
            "target": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolvePackageUsage_target),
            "packageName": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolvePackageUsage_packageName),
            "productName": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolvePackageUsage_productName),
        ])
        let swiftPackage = try GraphQLObjectType(name: "SwiftPackage", fields: [
            "name": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveSwiftPackage_name),
            "identity": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveSwiftPackage_identity),
            "url": GraphQLField(type: string, resolve: XQResolvers.resolveSwiftPackage_url),
            "requirement": GraphQLField(type: GraphQLNonNull(packageRequirement), resolve: XQResolvers.resolveSwiftPackage_requirement),
            "products": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(packageProduct))), resolve: XQResolvers.resolveSwiftPackage_products),
            "consumers": GraphQLField(type: GraphQLNonNull(GraphQLList(GraphQLNonNull(packageConsumer))), resolve: XQResolvers.resolveSwiftPackage_consumers),
        ])

        // BuildSetting object used by Target.buildSettings
        let buildSetting = try GraphQLObjectType(name: "BuildSetting", fields: [
            "configuration": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveBuildSetting_configuration),
            "key": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveBuildSetting_key),
            "value": GraphQLField(type: string, resolve: XQResolvers.resolveBuildSetting_value),
            "values": GraphQLField(type: GraphQLList(GraphQLNonNull(string)), resolve: XQResolvers.resolveBuildSetting_values),
            "isArray": GraphQLField(type: GraphQLNonNull(boolean), resolve: XQResolvers.resolveBuildSetting_isArray),
            "origin": GraphQLField(type: GraphQLNonNull(buildSettingOrigin), resolve: XQResolvers.resolveBuildSetting_origin),
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
            "linkDependencies": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(linkDependency))),
                args: [
                    "pathMode": GraphQLArgument(type: pathMode, defaultValue: Map("FILE_REF")),
                    "filter": GraphQLArgument(type: linkFilter)
                ],
                resolve: XQResolvers.resolveTarget_linkDependencies
            ),
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
            "packageProducts": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(packageProductUsage))),
                args: ["filter": GraphQLArgument(type: packageProductFilter)],
                resolve: XQResolvers.resolveTarget_packageProducts
            ),
            "buildSettings": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(buildSetting))),
                args: [
                    "scope": GraphQLArgument(type: buildSettingsScope, defaultValue: Map("TARGET_ONLY")),
                    "filter": GraphQLArgument(type: buildSettingFilter)
                ],
                resolve: XQResolvers.resolveTarget_buildSettings
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
        let targetLinkDependency = try GraphQLObjectType(name: "TargetLinkDependency", fields: [
            "target": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveFlatLink_target),
            "name": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveFlatLink_name),
            "kind": GraphQLField(type: GraphQLNonNull(linkKind), resolve: XQResolvers.resolveFlatLink_kind),
            "path": GraphQLField(type: string, resolve: XQResolvers.resolveFlatLink_path),
            "embed": GraphQLField(type: GraphQLNonNull(boolean), resolve: XQResolvers.resolveFlatLink_embed),
            "weak": GraphQLField(type: GraphQLNonNull(boolean), resolve: XQResolvers.resolveFlatLink_weak),
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
        let targetBuildSetting = try GraphQLObjectType(name: "TargetBuildSetting", fields: [
            "target": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveTargetBuildSetting_target),
            "configuration": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveTargetBuildSetting_configuration),
            "key": GraphQLField(type: GraphQLNonNull(string), resolve: XQResolvers.resolveTargetBuildSetting_key),
            "value": GraphQLField(type: string, resolve: XQResolvers.resolveTargetBuildSetting_value),
            "values": GraphQLField(type: GraphQLList(GraphQLNonNull(string)), resolve: XQResolvers.resolveTargetBuildSetting_values),
            "isArray": GraphQLField(type: GraphQLNonNull(boolean), resolve: XQResolvers.resolveTargetBuildSetting_isArray),
            "origin": GraphQLField(type: GraphQLNonNull(buildSettingOrigin), resolve: XQResolvers.resolveTargetBuildSetting_origin),
        ])
        // (buildSetting defined above)

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
            "targetBuildSettings": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(targetBuildSetting))),
                args: [
                    "scope": GraphQLArgument(type: buildSettingsScope, defaultValue: Map("TARGET_ONLY")),
                    "filter": GraphQLArgument(type: buildSettingFilter)
                ],
                resolve: XQResolvers.resolveTargetBuildSettings
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
            "targetLinkDependencies": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(targetLinkDependency))),
                args: [
                    "filter": GraphQLArgument(type: linkFilter)
                ],
                resolve: XQResolvers.resolveTargetLinkDependencies
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
            "swiftPackages": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(swiftPackage))),
                args: ["filter": GraphQLArgument(type: swiftPackageFilter)],
                resolve: XQResolvers.resolveSwiftPackages
            ),
            "targetPackageProducts": GraphQLField(
                type: GraphQLNonNull(GraphQLList(GraphQLNonNull(packageProductUsage))),
                args: ["filter": GraphQLArgument(type: packageProductUsageFilter)],
                resolve: XQResolvers.resolveTargetPackageProducts
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
