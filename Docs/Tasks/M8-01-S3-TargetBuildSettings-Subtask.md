# M8-01 — S3 Target Build Settings (most complex)

Instructions for Codex Agent

Goal
- Add a top-level query `targetBuildSettings(scope: BuildSettingsScope = TARGET_ONLY, filter: BuildSettingFilter): [TargetBuildSetting!]!` that returns build settings for each target across all configurations by default, with optional project/target/merged scoping.

Schema Additions
- In `Sources/XcodeQueryKit/GraphQLSwiftSchema.swift`:
  - Enums:
    - `enum BuildSettingsScope { PROJECT_ONLY, TARGET_ONLY, MERGED }` (default TARGET_ONLY)
    - `enum BuildSettingOrigin { PROJECT, TARGET }`
  - Inputs:
    - `input BuildSettingFilter { key: StringMatch, configuration: StringMatch, target: StringMatch }`
  - Objects:
    - `type TargetBuildSetting { target: String!, configuration: String!, key: String!, value: String, values: [String!], isArray: Boolean!, origin: BuildSettingOrigin! }`
  - Root field:
    - `targetBuildSettings(scope: BuildSettingsScope = TARGET_ONLY, filter: BuildSettingFilter): [TargetBuildSetting!]!`

Behavior
- Default includes all configurations available to each target (and project, for MERGED). Use `filter.configuration` to limit by name.
- Rows are per `(target, configuration, key)`.
- Sorting: ascending by `target`, then `configuration`, then `key`.
- Filtering:
  - `filter.target` applies to target name.
  - `filter.configuration` applies to configuration name.
  - `filter.key` applies to build setting key.
- Scope semantics:
  - `TARGET_ONLY` (default): rows come from target’s `XCBuildConfiguration` only, `origin = TARGET`.
  - `PROJECT_ONLY`: rows come from project-level `XCBuildConfiguration` only, `origin = PROJECT` (still flattened per target name to keep a uniform shape).
  - `MERGED`: union configuration names from project+target; for each `(target, configuration)` compute a merged dictionary where target values override project values, row `origin` reflects the final value’s source.
- Value normalization matches S2: arrays → `values/isArray`, scalars → `value`.
- Unknown configuration filters match nothing (no errors).

Resolver
- In `Sources/XcodeQueryKit/GraphQLSwiftResolvers.swift` add `XQResolvers.resolveTargetBuildSettings`:
  - Enumerate targets: `project.pbxproj.nativeTargets`.
  - For each target, collect "candidate configuration names":
    - `TARGET_ONLY`: target’s own configuration names.
    - `PROJECT_ONLY`: project configuration names.
    - `MERGED`: union(target config names, project config names).
  - For each candidate configuration name `c`:
    - Fetch project-level settings for `c` (if present).
    - Fetch target-level settings for `c` (if present).
    - Depending on `scope`:
      - `TARGET_ONLY`: use target settings only.
      - `PROJECT_ONLY`: use project settings only.
      - `MERGED`: shallow merge where target overrides project per key; track per-key origin for the final value.
  - Transform to rows `(target, configuration, key)` and apply filters.
  - Normalize values; set `origin` as `TARGET` or `PROJECT` based on selected source.
  - Sort rows: `(target, configuration, key)` ascending.

Implementation Notes
- Introduce small wrappers if needed (e.g., `GTargetBuildSetting`) for GraphQL source objects to implement field resolvers consistently.
- Add small helpers:
  - `allConfigurationNames(project:) -> [String]` (unique sorted)
  - `targetConfigurationNames(target:) -> [String]`
  - `normalizeBuildSettingValue(_ any: Any) -> (value: String?, values: [String]?, isArray: Bool)`
  - `mergeSettings(project: [String: Any], target: [String: Any]) -> (merged: [String: Any], originByKey: [String: BuildSettingOrigin])`

Tests (must cover everything)
- Resolver tests in `Tests/XcodeQueryKitTests/GraphQLSwiftResolverTests.swift`:
  - Default TARGET_ONLY path returns rows across all target configurations; verify subset for a specific target.
  - Filters:
    - `target.eq` limits to one target.
    - `configuration.eq` limits to one configuration.
    - `key.prefix`/`key.contains` reduce keys as expected.
  - Scope behavior:
    - `PROJECT_ONLY` yields only project values; `origin = PROJECT`.
    - `TARGET_ONLY` yields only target values; `origin = TARGET`.
    - `MERGED` prefers target keys; verify `origin` per key.
  - Value normalization for both scalar and array settings.
  - Stable sorting by `(target, configuration, key)`.
- Schema adapter tests in `Tests/XcodeQueryKitTests/SchemaAdapterTests.swift`:
  - Enum presence (`BuildSettingsScope`, `BuildSettingOrigin`).
  - Input presence and keys (`BuildSettingFilter` with `key`, `configuration`, `target`).
  - Object presence and fields (`TargetBuildSetting`).
  - Root field presence and default argument value for `scope`.

Acceptance Criteria
- `targetBuildSettings` returns deterministic JSON for the fixture project, across all configurations by default, with documented scoping/filters.
- All test cases pass.

Out of Scope
- `.xcconfig` include parsing.
- Macro expansion beyond raw values.

