# M13-01 — Phase 1: CLI Flag and Session Model for Workspace

Goal: Add `--workspace` flag to CLI and generalize the query session to support 1..N projects loaded from a workspace.

## Tasks

1) CLI changes
   - In `QueryCommand` and `InteractiveCommand`, add `--workspace PATH`.
   - Enforce mutual exclusivity with `--project`.

2) Session changes
   - Introduce a new `XcodeQuerySession` capable of holding either:
     - single `(projectPath, XcodeProj)`; or
     - a set from `(workspacePath, [ProjectContext])`.
   - Preserve current API for `evaluate(query:)`.

3) Back-compat
   - When `--project` is used (or default CWD autodetected), behavior identical to current.

## Acceptance Criteria

- CLI parses and validates flags; help text updated.
- Session loads workspace projects when provided.

