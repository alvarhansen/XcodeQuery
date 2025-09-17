# M6-01 Phase 3 — Dual Execution Harness

Goal
- Run the legacy parser and GraphQLSwift pipeline side-by-side to validate parity before cutting over the CLI.

Context
- We now have a schema and resolvers ready in GraphQLSwift, but production still relies on the bespoke parser. A controlled comparison phase reduces risk and surfaces incompatibilities early.

Tasks
- Introduce a feature flag (build setting, environment variable, or CLI hidden flag) to opt into GraphQLSwift execution.
- Build a harness that can execute a query through both pipelines and diff JSON outputs and error payloads in tests.
- Extend integration tests from Phase 0 to exercise the dual-path harness, failing fast on mismatches.
- Capture performance metrics (latency/memory) for each path to ensure no regressions prior to flip.
- Document the procedure for running parity comparisons locally and in CI.

Deliverables
- Feature-flagged GraphQLSwift execution path integrated into `XcodeQueryCLI`.
- Test utilities asserting structural equality between legacy and new outputs.
- Reports or logging capturing parity status and performance observations.

Dependencies
- Requires Phase 1 schema and Phase 2 resolvers to be functional.
- Builds upon Phase 0 golden tests to detect differences.

Risks & Mitigations
- Risk: Tests become flaky due to nondeterministic ordering. Mitigation: normalize output ordering before comparison.
- Risk: Feature flag leaks to users prematurely. Mitigation: keep flag internal/default-off and hide behind compile-time or env gating.
