# Linker Inputs & Embedding — Plan & Spec

Expose per-target link dependencies (frameworks, libraries, package products) and whether frameworks are embedded.

## Objectives

- List link inputs from `PBXFrameworksBuildPhase` with kind classification and optional path.
- Identify embedded frameworks via `PBXCopyFilesBuildPhase` (Frameworks destination) and weak linking.
- Provide flat view for piping and filters by name/kind.

Non-goals (initial):
- Deep SDK resolution beyond names for system frameworks; path optional for SDK items.

## UX Overview

- Nested: `target(name: "App") { linkDependencies(pathMode: NORMALIZED) { name kind path embed weak } }`
- Flat: `targetLinkDependencies { target name kind embed } | jq ...`
- Filter: `targetLinkDependencies(filter: { kind: FRAMEWORK, name: { suffix: ".framework" } }) { ... }`

## CLI Additions

- None required; query-surface only.

## Schema & Types

- Target addition
  - `linkDependencies(pathMode: PathMode = FILE_REF, filter: LinkFilter): [LinkDependency!]!`
- Flat view
  - `targetLinkDependencies(filter: LinkFilter): [TargetLinkDependency!]!`

Types
- `type LinkDependency { name: String!, kind: LinkKind!, path: String, embed: Boolean!, weak: Boolean! }`
- `type TargetLinkDependency { target: String!, name: String!, kind: LinkKind!, path: String, embed: Boolean!, weak: Boolean! }`

Enum
- `enum LinkKind { FRAMEWORK, LIBRARY, SDK_FRAMEWORK, SDK_LIBRARY, PACKAGE_PRODUCT, OTHER }`

Input
- `input LinkFilter { name: StringMatch, kind: LinkKind, target: StringMatch }`

## Architecture & Components

- Inspect `PBXFrameworksBuildPhase` build files:
  - Classify by file extension (.framework/.a/.dylib), SDK vs local, or package product reference.
  - Weak linking via `ATTRIBUTES` contains `Weak` on `PBXBuildFile.settings`.
- Embed detection:
  - `PBXCopyFilesBuildPhase` with destination `.frameworks` including the framework → `embed = true`.
- Path formatting respects `pathMode` similar to sources/resources.

## Testing Strategy

- Fixture with:
  - Linked SDK frameworks (UIKit.framework), local `.framework`, static `.a`, and package product.
  - Embedded local framework in App target.
- Assertions:
  - Correct kind classification, `embed` true/false, and `weak` flag.
  - Flat view ordering by `target`, then `name`.

## Implementation Tasks

1) Schema: types/enums/inputs and root flat view
2) Resolvers: per-target link scan + embed detection, path formatting
3) Filters/sorting and tests
4) Docs and release notes

## Milestones & Estimates

- M11-01 (Schema): 0.25 day
- M11-02 (Resolvers): 0.75–1 day
- M11-03 (Tests/docs): 0.5 day

## Risks & Mitigations

- Ambiguous product vs file reference for package products: rely on `XCSwiftPackageProductDependency` to label PACKAGE_PRODUCT where possible; otherwise classify as OTHER.
- Path resolution for SDK items: keep `path` nil for SDK_* kinds.

