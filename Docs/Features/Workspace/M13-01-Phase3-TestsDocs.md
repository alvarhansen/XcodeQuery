# M13-01 — Phase 3: Workspace Tests & Docs

Goal: Add tests and user docs for workspace mode.

## Tests

- Fixture: `.xcworkspace` with AppProject and LibProject.
- Assertions:
  - `projects` root field lists both projects and their targets.
  - `schemes` includes workspace-level shared schemes.
  - CLI: `--workspace` works with `query` and non-TTY `interactive`.

## Docs

- Readme: add a Workspace section with examples and notes about mutual exclusivity with `--project`.
- Release notes: Unreleased section itemizing new flag and root field.

## Acceptance Criteria

- Tests pass; docs match behavior.

