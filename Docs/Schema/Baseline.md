# XcodeQuery GraphQL Baseline Contract (Phase 0)

Goal
- Freeze the current query surface and behavior so later phases (GraphQLSwift migration) can assert parity.

Scope
- CLI accepts a selection-only GraphQL-style query (no top-level braces).
- Results are encoded to JSON with stable shapes documented here.

Top-level Fields (selection required)
- `targets(type: TargetType, filter: TargetFilter): [Target!]!`
- `target(name: String!): Target`
- `dependencies(name: String!, recursive: Boolean = false, filter: TargetFilter): [Target!]!`
- `dependents(name: String!, recursive: Boolean = false, filter: TargetFilter): [Target!]!`
- `targetSources(pathMode: PathMode = FILE_REF, filter: SourceFilter): [TargetSource!]!`
- `targetResources(pathMode: PathMode = FILE_REF, filter: ResourceFilter): [TargetResource!]!`
- `targetDependencies(recursive: Boolean = false, filter: TargetFilter): [TargetDependency!]!`
- `targetBuildScripts(filter: BuildScriptFilter): [TargetBuildScript!]!`
- `targetMembership(path: String!, pathMode: PathMode = FILE_REF): TargetMembership!`

Object Types
- `type Target { name: String!, type: TargetType!, dependencies(recursive: Boolean = false, filter: TargetFilter): [Target!]!, sources(pathMode: PathMode = FILE_REF, filter: SourceFilter): [Source!]!, resources(pathMode: PathMode = FILE_REF, filter: ResourceFilter): [Resource!]!, buildScripts(filter: BuildScriptFilter): [BuildScript!]! }`
- `type Source { path: String! }`
- `type Resource { path: String! }`
- `type BuildScript { name: String, stage: ScriptStage!, inputPaths: [String!]!, outputPaths: [String!]!, inputFileListPaths: [String!]!, outputFileListPaths: [String!]! }`
- `type TargetSource { target: String!, path: String! }`
- `type TargetResource { target: String!, path: String! }`
- `type TargetDependency { target: String!, name: String!, type: TargetType! }`
- `type TargetBuildScript { target: String!, name: String, stage: ScriptStage!, inputPaths: [String!]!, outputPaths: [String!]!, inputFileListPaths: [String!]!, outputFileListPaths: [String!]! }`
- `type TargetMembership { path: String!, targets: [String!]! }`

Enums
- `enum TargetType (APP, FRAMEWORK, STATIC_LIBRARY, DYNAMIC_LIBRARY, UNIT_TEST, UI_TEST, EXTENSION, BUNDLE, COMMAND_LINE_TOOL, WATCH_APP, WATCH2_APP, TV_APP, OTHER)`
- `enum PathMode (FILE_REF, ABSOLUTE, NORMALIZED)`
- `enum ScriptStage (PRE, POST)`

Input Objects (filters)
- `input StringMatch { eq: String, regex: String, prefix: String, suffix: String, contains: String }`
- `input TargetFilter { name: StringMatch, type: TargetType }`
- `input SourceFilter { path: StringMatch, target: StringMatch }`
- `input ResourceFilter { path: StringMatch, target: StringMatch }`
- `input BuildScriptFilter { stage: ScriptStage, name: StringMatch, target: StringMatch }`

Behavioral Notes & Quirks
- No top-level braces: queries must start with a field (e.g., `targets { name }`). Using `{ ... }` yields `Top-level braces are not supported. Write selection only, e.g., targets { name type }`.
- Whitespace is tolerant; optional commas between fields are accepted.
- Scalars: strings require double quotes with C-style escapes (\" \\ \n \t). Booleans are `true`/`false`. `null` is accepted for values but rarely used.
- Enums are bare identifiers (e.g., `UNIT_TEST`).
- Selection sets are required for all top-level fields and nested object-returning fields. Errors include:
  - `targets requires a selection set`
  - `target requires a selection set`
  - `dependencies/dependents requires a selection set`
  - `sources/resources/buildScripts requires selection set` when nested under `Target`.
- Argument defaults:
  - `recursive: false` for dependency-related fields.
  - `pathMode: FILE_REF` for source/resource fields and flat views.
- Path modes:
  - `FILE_REF`: raw PBX file reference path/name.
  - `ABSOLUTE`: standardized absolute paths.
  - `NORMALIZED`: path relative to project root when under it, otherwise absolute.
- Error strings (locked):
  - Parse errors: `Parse error: <message> @<position>` (e.g., `Unterminated string literal`, `Expected '}'`, `Expected identifier`, `Unexpected end of input`).
  - Execution errors: `Unknown top-level field: <name>`, `Unknown field on Target: <name>`, `Unknown field: <name>` for leaf projections, `Unknown target: <name>`, `name: String! required`, `path: String! required`.

Representative Examples
- `targets { name type }`
- `dependencies(name: "App", recursive: true) { name type }`
- `targets(type: UNIT_TEST) { name dependencies(recursive: true) { name } }`
- `targetSources(pathMode: NORMALIZED) { target path }`
- `targetBuildScripts(filter: { stage: PRE }) { target name stage }`
- `targetMembership(path: "Shared/Shared.swift", pathMode: NORMALIZED) { path targets }`

Testing Artifacts
- Golden JSON snapshots for representative queries: `Tests/XcodeQueryKitTests/Snapshots/GraphQLBaseline/*`.
- Failure-mode tests for parse and execution errors live in `Tests/XcodeQueryKitTests/GraphQLErrorTests.swift`.

Provenance
- This schema mirrors the GraphQLSwift runtime schema (`Sources/XcodeQueryKit/GraphQLSwiftSchema.swift`) and is used by the CLI via an adapter (`XQSchemaBuilder`).
