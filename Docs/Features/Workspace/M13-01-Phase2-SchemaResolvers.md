# M13-01 — Phase 2: Schema and Resolvers for Workspace Projects

Goal: Add `projects` root field, implement workspace scheme inclusion, and aggregate existing root fields across all projects when a workspace is loaded. Adopt Option A collision handling (keep duplicates; add disambiguators and deterministic sort).

## Tasks

1) Schema additions
   - `type Project { name: String!, path: String!, targets: [Target!]! }`
   - `projects: [Project!]!` root field.

2) Resolvers
   - Build `Project` objects from loaded workspace contexts.
   - For `schemes` root field, if workspace is loaded, include schemes from workspace `xcshareddata`.
   - Aggregate existing root fields across all loaded projects when in workspace mode:
     - `targets`, `targetSources`, `targetBuildSettings`, `schemes` (union of project-level + workspace-level where applicable).
   - Ensure filtering and sorting apply over the aggregated sets with stable, deterministic ordering.
   - Collisions (Option A):
     - Do not dedupe by name; return all matches.
     - Disambiguators (paths where sufficient):
       - Targets: include `project { name path }` on `Target` so callers can join via `(project.path, name)`.
       - Schemes: include `path: String!` to the `.xcscheme` and `container { kind project { name path } }`.
       - Flat views with a `target` field: add `targetProjectPath: String!` to join back to `targets` via `(targetProjectPath, target)`.
     - Sorting: by `project.path`, then entity `name`, then `project.name`; flat views then by `path`/`key` as applicable.

3) Sorting
   - Sort projects by `name`, then `path`.
   - Targets under a project sorted by `name`.

## Acceptance Criteria

- `projects { name path targets { name } }` returns expected values for a fixture with two projects.
- `schemes` includes workspace schemes when in workspace mode.
- Aggregation: `targets { name }` returns targets from both projects; simple filters (`name: { suffix: "App" }`) work across the union.
- Collisions: when two projects have an `App` target and `Run` scheme, both appear; `targets { name project { path } }` disambiguates; `schemes { name path container { kind project { name } } }` shows proper containment; `targetSources { target targetProjectPath path }` carries `targetProjectPath`.
