# M8-01 — S2 Project Build Settings (medium)

Instructions for Codex Agent

Goal
- Add a top-level query `projectBuildSettings(filter: ProjectBuildSettingFilter): [ProjectBuildSetting!]!` that returns build settings from the project-level build configurations across all configurations by default.

Schema Additions
- In `Sources/XcodeQueryKit/GraphQLSwiftSchema.swift`:
  - Input: `input ProjectBuildSettingFilter { key: StringMatch, configuration: StringMatch }`
  - Object: `type ProjectBuildSetting { configuration: String!, key: String!, value: String, values: [String!], isArray: Boolean! }`
  - Root field: `projectBuildSettings(filter: ProjectBuildSettingFilter): [ProjectBuildSetting!]!`

Behavior
- Default includes all configurations present on the project. Use `filter.configuration` to narrow by name (supports `eq`, `prefix`, `suffix`, `contains`, `regex`).
- Each row represents one `(configuration, key)` pair.
- Sorting: ascending by `configuration`, then `key`.
- Value normalization:
  - If XcodeProj provides an array (e.g., `[String]`), set `values` and `isArray = true`.
  - Otherwise set `value = String(describing: raw)` and `isArray = false`.
- Unknown configuration names in filter do not error; they simply match nothing.

Resolver
- In `Sources/XcodeQueryKit/GraphQLSwiftResolvers.swift` add `XQResolvers.resolveProjectBuildSettings`:
  - Collect project-level configuration names from `project.pbxproj.buildConfigurationList`.
  - For each configuration `c`, fetch its `buildSettings` dictionary.
  - Transform into rows and apply filters:
    - `filter.configuration` applied to `c`.
    - `filter.key` applied to each setting key.
  - Normalize values to `(value | values, isArray)` per rules above.
  - Sort rows: `(configuration, key)` ascending.
  - Return `[GProjectBuildSetting]` wrapper objects if needed for field resolvers, or a plain dictionary if you choose field-level resolvers.

Tests (must cover everything)
- Resolver tests in `Tests/XcodeQueryKitTests/GraphQLSwiftResolverTests.swift`:
  - Returns rows for all project configurations (fixture should have at least Debug/Release).
  - Filtering by `configuration.eq` and by `key.prefix` and `key.contains`.
  - Array vs scalar normalization (`values` vs `value`, `isArray` flag correctness).
  - Stable sorting by `(configuration, key)`.
- Schema adapter tests in `Tests/XcodeQueryKitTests/SchemaAdapterTests.swift`:
  - `ProjectBuildSetting` object exists; `projectBuildSettings` field exists with expected args.
  - `ProjectBuildSettingFilter` input exists and includes `key` and `configuration`.

Acceptance Criteria
- `projectBuildSettings` returns deterministic JSON with the described shape, across all configurations by default.
- All test cases pass.

Notes
- Do not attempt to resolve `.xcconfig` includes in this subtask.
- No macro expansion; return raw values from the project model.

