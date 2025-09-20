# M8-01 — S1 Build Configurations (easiest)

Instructions for Codex Agent

Goal
- Add a top-level query `buildConfigurations: [String!]!` that returns a unique, sorted list of build configuration names present in the project and any targets.

Scope
- GraphQL schema only: a single root field returning `[String!]!`.
- Resolver collects configuration names from both project-level and target-level build configuration lists.

Deliverables
- Schema: add `buildConfigurations: [String!]!` to `Query` in `Sources/XcodeQueryKit/GraphQLSwiftSchema.swift`.
- Resolver: implement `XQResolvers.resolveBuildConfigurations` in `Sources/XcodeQueryKit/GraphQLSwiftResolvers.swift`.
  - Enumerate `project.pbxproj.buildConfigurationList?.buildConfigurations.map(\.name)` and union with names from each `PBXNativeTarget.buildConfigurationList?.buildConfigurations`.
  - Return a deduplicated, alphabetically sorted array of names.
- Tests (must cover everything):
  - Add a resolver test in `Tests/XcodeQueryKitTests/GraphQLSwiftResolverTests.swift` executing `buildConfigurations` against the fixture project; assert the returned set and sort order.
  - Add a schema/adapter test in `Tests/XcodeQueryKitTests/SchemaAdapterTests.swift` (or a new test file) that verifies the field exists on the query root via `XQSchemaBuilder.fromGraphQLSwift()`.

Acceptance Criteria
- `graphql(schema:..., request: "buildConfigurations", ...)` returns a JSON array of strings, unique and sorted.
- Tests pass on macOS with `swift test`.

Notes
- This field has no arguments and performs no I/O beyond reading the in-memory project from the context.

