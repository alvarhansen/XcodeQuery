# GraphQL Usage & Requirements in XcodeQuery CLI

Date: 2026-02-01

## Overview
XcodeQuery’s CLI is built around a GraphQL-style selection language. The current implementation uses the GraphQLSwift `GraphQL` package for both:
- **Runtime query parsing/execution** (evaluate queries against an `XcodeProj` instance).
- **Schema introspection** (SchemaCommand + autocomplete model generation).

The CLI only accepts a **selection set** (no top-level braces). The code wraps the input in `{ ... }` and hands it to the GraphQLSwift executor.

Key entry points:
- `query` command -> `XcodeProjectQuery.evaluate(query:)` -> `graphql(...)`.
- `interactive` command -> `XcodeProjectQuerySession.evaluate(query:)` -> `graphql(...)`.
- `schema` command + `CompletionProvider` -> `XQSchemaBuilder.fromGraphQLSwift()` -> introspects `GraphQLSchema`.

Sources: `Sources/XcodeQueryKit/XcodeProjectQuery.swift`, `Sources/XcodeQueryKit/XcodeProjectQuerySession.swift`, `Sources/XcodeQueryKit/XQSchemaBuilder.swift`, `Sources/XcodeQueryCLI/QueryCommand.swift`, `Sources/XcodeQueryCLI/InteractiveSession.swift`, `Sources/XcodeQueryCLI/SchemaCommand.swift`, `Sources/XcodeQueryCLI/CompletionProvider.swift`.

## GraphQL Library Features Actually Used

### 1) Execution/Parsing
Used directly in:
- `XcodeProjectQuery.evaluateWithGraphQLSwift(...)`
- `XcodeProjectQuerySession.evaluateWithGraphQLSwift(...)`
- `Tests/XcodeQueryKitTests/GraphQLSwiftResolverTests.swift`

Required API surface:
- `graphql(schema:request:context:eventLoopGroup)` executor.
- `GraphQLSchema` for the runtime schema.
- `GraphQLResult` / result object with `.data` (as `Map`) and `.errors`.
- Error propagation: returned `.errors` and thrown `GraphQLError` from resolvers.
- **Argument values** exposed as `Map` with accessors:
  - `.string`, `.bool`, `.int`, `.double`, `.dictionary`, `.array`.
  - `.isNull`, `.isUndefined`.

### 2) Type System / Schema Construction
Used in `Sources/XcodeQueryKit/GraphQLSwiftSchema.swift`.

Constructed types:
- `GraphQLSchema`
- `GraphQLObjectType`
- `GraphQLInputObjectType`
- `GraphQLEnumType`, `GraphQLEnumValue`
- `GraphQLField`, `GraphQLArgument`
- `GraphQLNonNull`, `GraphQLList`
- Built-in scalars: `GraphQLString`, `GraphQLBoolean`
- `Map` as enum/default-value carriers

### 3) Schema Introspection (SchemaCommand + Autocomplete)
Used in `Sources/XcodeQueryKit/XQSchemaBuilder.swift`.

Required API surface:
- `GraphQLSchema.typeMap` enumeration.
- Access to `GraphQLObjectType.fields`, `GraphQLInputObjectType.fields`, `GraphQLEnumType.values`.
- Access to `GraphQLArgumentDefinition` (name, type, defaultValue).
- Type helpers: `GraphQLType`, `GraphQLInputType`, `GraphQLNonNull`, `GraphQLList`, and `getNamedType(...)`.
- Default value formatting based on `Map` (bool/string/int/double).

### 4) Resolver Signatures
Used heavily in `Sources/XcodeQueryKit/GraphQLSwiftResolvers.swift`.

Required API surface:
- Resolver signature inputs: `(source: Any, args: Map, context: Any, info: GraphQLResolveInfo)`.
- Ability to return Swift arrays/structs/strings that GraphQLSwift serializes.
- `GraphQLFieldResolveInput` (closure type) for resolver factories.
- `GraphQLError` for custom execution errors.

### 5) NIO Event Loop Integration
Execution uses NIO:
- `MultiThreadedEventLoopGroup(numberOfThreads: 1)` in both `XcodeProjectQuery` and tests.

Any replacement runtime should either:
- Offer an equivalent synchronous API, or
- Provide a simple event loop abstraction (current code uses `wait()` on the future).

## Query Surface Actually Exposed (Current Runtime Schema)

The **actual** schema comes from `GraphQLSwiftSchema.swift`, which is larger than the baseline doc. Top-level fields include:
- `buildConfigurations`
- `projectBuildSettings(filter: ProjectBuildSettingFilter)`
- `targetBuildSettings(scope: BuildSettingsScope = TARGET_ONLY, filter: BuildSettingFilter)`
- `targets(type: TargetType, filter: TargetFilter)`
- `target(name: String!)`
- `dependencies(name: String!, recursive: Boolean = false, filter: TargetFilter)`
- `dependents(name: String!, recursive: Boolean = false, filter: TargetFilter)`
- `targetSources(pathMode: PathMode = FILE_REF, filter: SourceFilter)`
- `targetResources(pathMode: PathMode = FILE_REF, filter: ResourceFilter)`
- `schemes(filter: SchemeFilter)`
- `targetLinkDependencies(filter: LinkFilter)`
- `targetDependencies(recursive: Boolean = false, filter: TargetFilter)`
- `targetBuildScripts(filter: BuildScriptFilter)`
- `swiftPackages(filter: SwiftPackageFilter)`
- `targetPackageProducts(filter: PackageProductUsageFilter)`
- `targetMembership(path: String!, pathMode: PathMode = FILE_REF)`

Key object types used by queries:
- Targets/sources/resources/build scripts: `Target`, `Source`, `Resource`, `BuildScript`, `TargetSource`, `TargetResource`, `TargetBuildScript`.
- Dependencies: `TargetDependency`, `LinkDependency`, `TargetLinkDependency`.
- Schemes: `Scheme`, `SchemeRef`.
- Build settings: `BuildSetting`, `ProjectBuildSetting`, `TargetBuildSetting`.
- Swift packages: `SwiftPackage`, `PackageRequirement`, `PackageProduct`, `PackageConsumer`, `PackageProductUsage`.

Filters/inputs (selection arguments):
- `StringMatch`, `TargetFilter`, `SourceFilter`, `ResourceFilter`, `BuildScriptFilter`,
  `ProjectBuildSettingFilter`, `BuildSettingFilter`, `SchemeFilter`, `LinkFilter`,
  `SwiftPackageFilter`, `PackageProductFilter`, `PackageProductUsageFilter`.

Enums used in arguments/fields:
- `TargetType`, `PathMode`, `ScriptStage`, `BuildSettingsScope`, `BuildSettingOrigin`,
  `LinkKind`, `RequirementKind`, `PackageProductType`.

## Error Behavior & Contractual Expectations
Tests assert specific behavior and error strings. Key expectations:
- **Selection-only input**: top-level braces are rejected with a specific message.
- **Selection set required** for object-returning fields (`targets`, `target`, nested object fields).
- **Argument validation**: missing required args produce errors referencing the arg name.
- **Parse errors**: messages include “unterminated” / “syntax” / “expected …”.
- **Resolver errors**: unknown target yields `Unknown target: <name>`.

Sources: `Tests/XcodeQueryKitTests/GraphQLErrorTests.swift`, `Docs/Schema/Baseline.md`.

## Output/Encoding Expectations
- Query results are serialized to JSON via `JSONEncoder`.
- Execution output uses GraphQLSwift’s `Map` -> bridged into `JSONValue`.
- Tests include **snapshot comparisons** with sorted keys for stable output.

Sources: `Sources/XcodeQueryKit/XcodeProjectQuery.swift`, `Tests/XcodeQueryKitTests/Support/GraphQLBaselineFixture.swift`, `Tests/XcodeQueryKitTests/Snapshots/GraphQLBaseline/*`.

## What the CLI Does NOT Use
These GraphQL features are not part of the current CLI surface:
- Mutations, subscriptions.
- Variables or operation definitions.
- Fragment definitions (not referenced by tests or CLI).
- GraphQL introspection queries (schema is rendered via custom model, not runtime introspection queries).

## Implications (If Replacing GraphQLSwift)
Any replacement must provide at least:
- A parser for GraphQL selection sets with arguments, input objects, enums, and strings.
- Validation for selection sets and required arguments with similar error strings.
- A runtime that can execute against the existing resolver graph and return a JSON-like map.
- A schema model rich enough to drive `SchemaCommand` and `CompletionProvider`.

If those pieces are not all available, the CLI/interactive experience will regress.
