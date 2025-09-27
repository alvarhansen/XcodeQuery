# M11-01 — Phase 2: Resolvers for Linker Inputs

Goal: Implement resolvers to scan framework/library links and detect embedding and weak linking.

## Tasks

1) Per-target scan
   - `PBXFrameworksBuildPhase.files` → collect `PBXBuildFile`.
   - Classify kind by associated file reference or product dependency.
   - `weak = settings["ATTRIBUTES"] contains "Weak"`.

2) Embed detection
   - `PBXCopyFilesBuildPhase` with destination frameworks; match names to linked frameworks → `embed = true`.

3) Flat view aggregation
   - Across all targets, emit `(target, name, kind, path?, embed, weak)` rows.

4) Filters and sorting
   - `name` via `StringMatch`, `kind` equals, optional `target` in flat view.
   - Sort by `target`, then `name` (flat) and by `name` (nested).

## Acceptance Criteria

- Deterministic output and accurate `embed/weak` flags for fixture targets.

