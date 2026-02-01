# M6-01 Phase 4 — CLI Flip and Fallback Strategy

Status
- Completed; internal runtime is the default execution path and the legacy fallback has been removed (2026-02-01).

Goal
- Make GraphQL runtime the default execution path for the CLI while retaining a temporary fallback to the legacy parser for emergency rollbacks.

Context
- After parity validation, the next milestone is switching user-facing execution to GraphQL runtime without disrupting workflows.

Tasks
- Update `GraphQL.parseAndExecute` (and related entry points) to route queries through GraphQL runtime by default.
- Retain the legacy parser behind a hidden flag or build toggle with telemetry/logging to detect if it is invoked.
- Refresh CLI integration tests to expect GraphQL runtime error messaging and ensure output snapshots still match Phase 0 baselines.
- Update documentation (README, Docs/Tasks, release notes draft) to note the internal runtime behavior.
- Coordinate with release/CI owners to ensure binary distribution includes the GraphQL runtime artifacts.

Deliverables
- Code changes flipping the default execution path.
- Updated test suite and documentation reflecting the new default.
- Rollback levers identified and documented for post-release monitoring.

Dependencies
- Requires successful completion of Phase 3 parity validation and performance sign-off.

Risks & Mitigations
- Risk: Undetected edge cases after flip. Mitigation: maintain fallback flag for at least one release cycle and monitor telemetry/bug reports.
- Risk: Packaging issues with the new dependency. Mitigation: validate `make release` and Homebrew packaging before merge.
