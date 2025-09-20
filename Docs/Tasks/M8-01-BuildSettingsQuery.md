# M8-01 — Build Settings Query

Goal
- Add a GraphQL-style query surface to inspect Xcode build settings per target and configuration, with clear scoping (project vs target) and predictable JSON output.

Context
- Teams frequently need to audit values like `SWIFT_VERSION`, `OTHER_SWIFT_FLAGS`, `INFOPLIST_FILE`, and code signing settings across targets/configurations.
- Current schema lacks any view into build settings; adding this enables scripting and CI checks without opening Xcode.
- Initial scope focuses on values stored in the Xcode project (project/target build configurations). Parsing and merging `.xcconfig` files can arrive in a follow-up.

UX & Schema
- Top-level fields (new):
  - `targetBuildSettings(scope: BuildSettingsScope = TARGET_ONLY, filter: BuildSettingFilter): [TargetBuildSetting!]!`
  - `projectBuildSettings(filter: ProjectBuildSettingFilter): [ProjectBuildSetting!]!`
  - `buildConfigurations: [String!]!`
- Nested on `Target` (new):
  - `buildSettings(scope: BuildSettingsScope = TARGET_ONLY, filter: BuildSettingFilter): [BuildSetting!]!`
- Object types (new):
  - `type BuildSetting { key: String!, value: String, values: [String!], isArray: Boolean!, origin: BuildSettingOrigin! }`
  - `type TargetBuildSetting { target: String!, configuration: String!, key: String!, value: String, values: [String!], isArray: Boolean!, origin: BuildSettingOrigin! }`
  - `type ProjectBuildSetting { configuration: String!, key: String!, value: String, values: [String!], isArray: Boolean! }`
- Enums (new):
  - `enum BuildSettingsScope { PROJECT_ONLY, TARGET_ONLY, MERGED }`
  - `enum BuildSettingOrigin { PROJECT, TARGET }`
- Inputs (new):
  - `input BuildSettingFilter { key: StringMatch, configuration: StringMatch, target: StringMatch }`
  - `input ProjectBuildSettingFilter { key: StringMatch, configuration: StringMatch }`

- Behavior
- Configurations returned by default: all matching configurations are included by default. Use `filter.configuration` to limit to one or more names. No error is thrown for unknown configuration names; unmatched filters simply yield no rows.
- `scope` controls data provenance (default TARGET_ONLY):
  - `PROJECT_ONLY`: read from project-level `XCBuildConfiguration` for the named configuration.
  - `TARGET_ONLY` (default): read from target-level `XCBuildConfiguration`.
  - `MERGED`: target settings override project settings (simple in-memory merge). Note: `.xcconfig` contents are not merged in the initial version.
- Values
  - Settings that XcodeProj exposes as arrays populate `values` and set `isArray = true`.
  - Scalar settings populate `value` and set `isArray = false`.
  - For MERGED, single result per final key.
- Origin
  - `origin` indicates where the reported value came from: `PROJECT` or `TARGET` (useful in `MERGED`). `.xcconfig` origin and paths arrive in a follow-up.
- Ordering: results are stable-sorted by `target` (if present), then `configuration`, then `key` ascending.
- Filtering: `filter.key` applies to the setting key; `filter.target` applies to the flattened view’s `target` field. For `projectBuildSettings`, only `key` is applicable via `ProjectBuildSettingFilter`.

CLI Examples
- Keys for a single target (merged) across all configs, limit to Debug via filter:
  - `target(name: "App") { buildSettings(scope: MERGED, filter: { configuration: { eq: "Debug" } }) { key value values isArray origin } }`
- All targets’ signing keys in Release:
  - `targetBuildSettings(filter: { configuration: { eq: "Release" }, key: { prefix: "CODE_SIGN" } }) { target configuration key value origin }`
- Project-only SWIFT flags across all configs:
  - `projectBuildSettings(filter: { key: { contains: "SWIFT" } }) { configuration key values }`
- List available configuration names:
  - `buildConfigurations`

Out of Scope (initial)
- Parsing/merging `.xcconfig` files referenced by `baseConfiguration`.
- Macro/variable expansion (e.g., `$(SRCROOT)`), and toolchain-derived defaults.
- Cross-configuration comparisons/diffs.

Implementation Plan
1) Schema additions (XcodeQueryKit)
   - Extend `Sources/XcodeQueryKit/GraphQLSwiftSchema.swift` with:
     - `BuildSettingsScope` enum (default TARGET_ONLY), `BuildSettingOrigin` enum.
     - Inputs: `BuildSettingFilter` (add `configuration`), `ProjectBuildSettingFilter` (add `configuration`).
     - Objects: `BuildSetting`, `TargetBuildSetting`, `ProjectBuildSetting`.
     - Fields: `Target.buildSettings(...)`, `Query.targetBuildSettings(...)`, `Query.projectBuildSettings(...)`, `Query.buildConfigurations`.
2) Resolvers (XcodeQueryKit)
   - Enumerate all configuration names from project and targets; implement helper returning a sorted unique list.
   - Implement scoped reads and simple merge (target overrides project) for `MERGED` across all configurations, applying `filter.configuration` when provided.
   - Normalize values:
     - Detect array-valued settings (populate `values`, `isArray = true`).
     - Otherwise populate `value`, `isArray = false`.
   - Implement filtering and stable sorting as described.
   - For `origin`: set `TARGET` for values sourced from target configs, `PROJECT` for project configs; in `MERGED`, reflect the chosen source for the final value.
3) Tests (XcodeQueryKitTests)
   - Fixture: ensure the generated project includes representative settings at project and target level (e.g., `SWIFT_VERSION`, `SWIFT_ACTIVE_COMPILATION_CONDITIONS`, `CODE_SIGNING_ALLOWED`, `INFOPLIST_FILE`).
   - Add resolver tests asserting:
     - Project-only vs target-only vs merged behavior.
     - Array vs scalar normalization.
     - Error messages for missing/unknown configuration.
   - Add schema adapter tests to verify new types/fields are present, including `buildConfigurations` and new filter keys.
   - Add small snapshot(s) for common queries under `Snapshots/` including `projectBuildSettings` and `buildConfigurations`.
4) CLI & Docs
   - `xcq schema` reflects the new fields automatically (via adapter); update `Docs/Schema/*` with a short section on Build Settings.
   - Update `Readme.md` with examples.

Acceptance Criteria
- `xcq schema` lists `targetBuildSettings` and `Target.buildSettings` with documented arguments and types.
- Queries return stable, deterministic JSON for a known fixture project across scopes.
- Tests cover normalization (value vs values), merging semantics, and errors.
- Interactive completions suggest `buildSettings`, `targetBuildSettings`, enum symbols for `BuildSettingsScope`, and `BuildSettingFilter` keys (driven by the schema model).

Risks & Mitigations
- `.xcconfig` not merged initially may surprise users.
  - Mitigation: document clearly in `Readme.md`; add a follow-up milestone to parse `.xcconfig` includes.
- Some settings’ underlying types vary by usage (string vs array).
  - Mitigation: dual fields (`value`/`values`) with `isArray` flag; tests lock shapes.
- Configuration name mismatches across targets.
  - Mitigation: error early for unknown configuration; for the flat view, include only targets that have the configuration.

Follow-ups
- M8-02 — `.xcconfig` resolution and include chain.
- M8-03 — Variable expansion for common macros (best-effort, opt-in).
