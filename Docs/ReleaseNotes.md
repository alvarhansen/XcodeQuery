# Release Notes

## v0.1.0 — Build Settings Queries, GraphQLSwift baseline

New
- Build configurations query
  - `buildConfigurations: [String!]!` returns unique, sorted configuration names.
- Project build settings
  - `projectBuildSettings(filter: { key, configuration })` returns `(configuration, key, value|values, isArray)` across all configurations by default.
- Per-target build settings (flat)
  - `targetBuildSettings(scope: BuildSettingsScope = TARGET_ONLY, filter: { target, configuration, key })` yields rows per `(target, configuration, key)` with `origin` indicating `PROJECT` or `TARGET`. Default includes all configurations.
- Nested per-target build settings
  - `target(name: ...) { buildSettings(scope: BuildSettingsScope = TARGET_ONLY, filter: { configuration, key }) { configuration key value values isArray origin } }`.
- Enums and inputs
  - `BuildSettingsScope { PROJECT_ONLY, TARGET_ONLY, MERGED }`, `BuildSettingOrigin { PROJECT, TARGET }`.
  - `ProjectBuildSettingFilter`, `BuildSettingFilter` include `StringMatch` keys (`eq`, `prefix`, `suffix`, `contains`, `regex`).

Improvements
- Schema source of truth
  - SchemaCommand renders from GraphQLSwift runtime schema via `XQSchemaBuilder`. CompletionProvider consumes the same model.
  - Deterministic alphabetical ordering in sections.
- GraphQLSwift execution only
  - Legacy parser/AST/executor removed. Error messages now originate from GraphQLSwift.

Docs
- Updated schema baseline and README with new fields, filters, and examples.

Migration notes
- If tooling referenced internal legacy types (e.g., `GQLError`, `GraphQLExecutor`), migrate to `XQGraphQLSwiftSchema` and `XQResolvers`.
- Regex arguments in queries must be properly escaped for GraphQL strings (e.g., `\"\\.swift$\"`).

## Unreleased

- 
## v0.1.1 — Packaging

- Lower Swift tools version to 6.1 for broader compatibility with environments pinned to Swift 6.1 toolchains (no functional changes).

