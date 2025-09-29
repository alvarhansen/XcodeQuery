# M13-01 — Phase 1: CLI Flag and Session Model for Workspace

Goal: Add `--workspace` flag to CLI and generalize the query session to support 1..N projects loaded from a workspace.

## Tasks

1) CLI changes
   - In `QueryCommand` and `InteractiveCommand`, add `--workspace PATH`.
   - Enforce mutual exclusivity with `--project`.
   - Default path resolution: when neither flag is provided, prefer a `.xcworkspace` in CWD; if none, fall back to `.xcodeproj` (match `xed`).

2) Session changes
   - Introduce a new `XcodeQuerySession` capable of holding either:
     - single `(projectPath, XcodeProj)`; or
     - a set from `(workspacePath, [ProjectContext])`.
   - Preserve current API for `evaluate(query:)`.
   - Behavior note: aggregation of existing root fields across multiple projects is implemented in Phase 2; Phase 1 focuses on flag plumbing and multi-project session support.

3) Back-compat
   - When `--project` is used, behavior identical to current single-project mode. When only a single project is loaded, behavior matches current semantics.

## Acceptance Criteria

- CLI parses and validates flags; help text updated.
- Session loads workspace projects when provided.
- Default search prefers workspace over project when no path flags are given.
