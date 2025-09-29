# M13-01 — Phase 3: Workspace Tests & Docs

Goal: Add tests and user docs for workspace mode.

## Tests

- Fixture: `.xcworkspace` with AppProject and LibProject.
- Assertions:
  - `projects` root field lists both projects and their targets.
  - `schemes` includes workspace-level shared schemes.
  - Aggregation: `targets { name }` returns targets from both projects; filters and sorting behave consistently across the aggregated set.
  - CLI: `--workspace` works with `query` and non-TTY `interactive`.
  - Collisions (Option A):
    - Duplicate target names across projects are preserved; `targets { name project { path } }` disambiguates by project path.
    - Duplicate scheme names at workspace vs project levels are preserved; `schemes { name path container { kind project { name } } }` disambiguates by file path and container.
    - Flat views include `targetProjectPath`: `targetSources { target targetProjectPath path }`, `targetBuildSettings { target targetProjectPath configuration key }`, etc.; verify `(targetProjectPath, target)` maps to an entry in `targets { name project { path } }`.

## Docs

 - Readme: add a Workspace section with examples, aggregation semantics for existing fields, collision handling (Option A) with path-based disambiguation (`project.path + target.name`, `.xcscheme` file `path`), and notes about mutual exclusivity with `--project`.
- Release notes: Unreleased section itemizing new flag and root field.

## Acceptance Criteria

- Tests pass; docs match behavior.
