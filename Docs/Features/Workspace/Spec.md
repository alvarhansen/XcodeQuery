# Workspace-Level Queries — Plan & Spec

Add workspace awareness to allow multi-project introspection and workspace-wide scheme listing.

## Objectives

- Load a `.xcworkspace` and aggregate member `.xcodeproj` projects.
- Provide a root `projects` field exposing per-project targets and path.
- Add workspace CLI flag so existing queries can operate over a workspace context.
- Extend `schemes` to include workspace schemes.
- Existing root fields aggregate across all projects when a workspace is loaded (e.g., `targets`, `targetSources`, `schemes`, `targetBuildSettings`).

Non-goals (initial):
- Cross-project dependency resolution beyond name matching.

## UX Overview

- CLI flag: `xcq 'projects { name path targets { name type } }' --workspace MyApp.xcworkspace`
- List workspace schemes: `schemes { name buildTargets { name } } --workspace MyApp.xcworkspace`
- Aggregate existing fields across the workspace: `targets { name type } --workspace MyApp.xcworkspace`
- Continue to support `--project` mode; `--workspace` and `--project` are mutually exclusive.

## CLI Additions

- `--workspace PATH` option for `query` and `interactive`.
- Precedence/validation: cannot combine with `--project`.
- Default path resolution (no flags provided): search the current directory for a `.xcworkspace` first; if none is found, use a `.xcodeproj`. This mirrors `xed` behavior.
- Semantics: when a workspace is loaded (via flag or default search), root fields operate over all member projects; when a single project is loaded, root fields operate over that project.

## Schema & Types

- Root
  - `projects: [Project!]!`
- Types
  - `type Project { name: String!, path: String!, targets: [Target!]! }`
  - Extend `Target` to include its container project reference for disambiguation:
    - `type Target { ... , project: ProjectRef! }`
    - `type ProjectRef { name: String!, path: String! }`
  - Extend `Scheme` to include workspace-aware disambiguators when a workspace is loaded:
    - `type Scheme { ... , path: String!, container: SchemeContainer! }`
    - `type SchemeContainer { kind: SchemeContainerKind!, project: ProjectRef }`
    - `enum SchemeContainerKind { WORKSPACE, PROJECT }`
  - Semantics: root fields such as `targets`, `targetSources`, `schemes`, and `targetBuildSettings` aggregate across all loaded projects when in workspace mode.

### Aggregation & Collisions (Option A)

- Policy: Keep duplicates; do not auto‑dedupe.
- Disambiguators exposed (prefer file paths where sufficient):
  - Targets: expose `project { name path }` on `Target` so callers can disambiguate using `project.path + target.name`. No ID when a path is sufficient; if we later find cases where path+name cannot disambiguate, we can introduce an `id` then.
  - Schemes: expose scheme file `path: String!` to the `.xcscheme` file and `container: SchemeContainer!` where `SchemeContainer` captures `kind: WORKSPACE|PROJECT` and `project { name path }` when applicable. No `id` required.
  - Flat views referencing a target (`TargetSource`, `TargetResource`, `TargetBuildScript`, `TargetBuildSetting`, `TargetDependency`): include `targetProjectPath: String!` alongside existing `target` string to enable joins back to a unique target key `(targetProjectPath, target)`.
- Deterministic sort order in aggregated mode:
  - Primary: `project.path`
  - Secondary: entity `name` (e.g., target/scheme name)
  - Tertiary: `project.name`
  - Flat views: sort by the above using their associated target’s `project.path`/`name`, then by the view’s own `path`/`key` where relevant.

### Paths & Normalization

- Normalize scheme and project paths to workspace‑relative when a workspace is loaded; otherwise use standardized absolute paths.
- Resolve symlinks (standardize file URLs) to ensure a single canonical path.
- Preserve case as on disk; treat comparisons as case‑insensitive on macOS when necessary for sorting.

## Architecture & Components

- Use `XCWorkspace` to enumerate project file references.
- Build an in-memory array of `(projectPath, XcodeProj)` contexts.
- Resolvers iterate across the loaded set of projects; existing root fields aggregate results across all projects when a workspace is loaded, preserving existing behavior for single-project contexts.

## Testing Strategy

- Fixture: workspace with two projects (AppProject, LibProject).
- Assertions:
  - `projects { name targets { name } }` contains both projects and their targets.
  - `schemes` includes schemes from workspace-level `xcshareddata` and exposes `path` and `container` for disambiguation.
  - Aggregation: `targets { name }` returns the union from all member projects; filters apply across the aggregated set and maintain stable, deterministic ordering.
- CLI: verify `--workspace` flag works for both `query` and `interactive` non-TTY mode.

## Implementation Tasks

1) CLI flag plumbing for `--workspace` in Query/Interactive commands (mutual exclusion)
2) Session layer: `XcodeProjectQuerySession` generalized to a `XcodeQuerySession` that can hold one or many projects
3) Schema: add `projects` type and root field; extend `schemes` to read workspace schemes and add `path`/`container` for disambiguation
4) Resolvers: aggregate existing root fields (`targets`, `targetSources`, `schemes`, `targetBuildSettings`, etc.) across all loaded projects; ensure sorting and filtering remain consistent
5) Tests and docs; release notes

## Milestones & Estimates

- M13-01 (CLI and session): 0.75 day
- M13-02 (Schema/resolvers): 1 day
- M13-03 (Tests/docs): 0.5 day

## Risks & Mitigations

- Name collisions across projects: when aggregating, consider prefixing target results with project name in flat views later (out of scope for initial pass).
- Large workspaces: ensure iteration remains efficient; reuse loaded `XcodeProj` instances.

## Open Questions

- Resolved: existing root fields aggregate across all workspace projects when in workspace mode. The `projects { ... }` surface remains for per-project detail.
