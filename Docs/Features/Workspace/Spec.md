# Workspace-Level Queries — Plan & Spec

Add workspace awareness to allow multi-project introspection and workspace-wide scheme listing.

## Objectives

- Load a `.xcworkspace` and aggregate member `.xcodeproj` projects.
- Provide a root `projects` field exposing per-project targets and path.
- Add workspace CLI flag so existing queries can operate over a workspace context.
- Extend `schemes` to include workspace schemes.

Non-goals (initial):
- Cross-project dependency resolution beyond name matching.

## UX Overview

- CLI flag: `xcq 'projects { name path targets { name type } }' --workspace MyApp.xcworkspace`
- List workspace schemes: `schemes { name buildTargets { name } } --workspace MyApp.xcworkspace`
- Continue to support `--project` mode; `--workspace` and `--project` are mutually exclusive.

## CLI Additions

- `--workspace PATH` option for `query` and `interactive`.
- Precedence/validation: cannot combine with `--project`. If neither is set, default to CWD `.xcodeproj` as today.

## Schema & Types

- Root
  - `projects: [Project!]!`
- Types
  - `type Project { name: String!, path: String!, targets: [Target!]! }`
  - Reuse existing `Target` type for nested targets where practical.

## Architecture & Components

- Use `XCWorkspace` to enumerate project file references.
- Build an in-memory array of `(projectPath, XcodeProj)` contexts.
- Resolvers operate across the set; existing top-level fields continue to operate on the loaded context (single or aggregated).

## Testing Strategy

- Fixture: workspace with two projects (AppProject, LibProject).
- Assertions:
  - `projects { name targets { name } }` contains both projects and their targets.
  - `schemes` includes schemes from workspace-level `xcshareddata`.
- CLI: verify `--workspace` flag works for both `query` and `interactive` non-TTY mode.

## Implementation Tasks

1) CLI flag plumbing for `--workspace` in Query/Interactive commands (mutual exclusion)
2) Session layer: `XcodeProjectQuerySession` generalized to a `XcodeQuerySession` that can hold one or many projects
3) Schema: add `projects` type and root field; extend `schemes` to read workspace schemes
4) Resolvers: adapt root field resolvers to iterate across projects where appropriate (minimal surface initially)
5) Tests and docs; release notes

## Milestones & Estimates

- M13-01 (CLI and session): 0.75 day
- M13-02 (Schema/resolvers): 1 day
- M13-03 (Tests/docs): 0.5 day

## Risks & Mitigations

- Name collisions across projects: when aggregating, consider prefixing target results with project name in flat views later (out of scope for initial pass).
- Large workspaces: ensure iteration remains efficient; reuse loaded `XcodeProj` instances.

## Open Questions

- Should existing root fields (`targets`, `targetSources`, etc.) aggregate across all workspace projects automatically when in workspace mode? Initial approach: keep semantics simple and add `projects { ... }` surface; revisit aggregation in a follow-up.

