# M6-01 Phase 0 — Baseline Fidelity Freeze

Goal
- Capture the current GraphQL surface, inputs, and outputs so that the GraphQLSwift migration can prove behavioral parity.

Context
- The bespoke parser/executor is still the single source of truth; we need durable documentation and tests before replacing it.
- Coverage today is uneven, especially for nested selections and error reporting, which complicates regression detection.

Tasks
- Inventory all root fields, arguments, nested selections, enums, and input records exposed by the CLI.
- Record quirks such as whitespace handling, brace tolerance, default argument values, and known error strings.
- Add golden-path integration tests in `Tests/XcodeQueryKitTests` that execute representative queries and snapshot the JSON results.
- Expand failure-mode tests to lock current error codes/messages for malformed queries, unknown fields, and type mismatches.
- Document findings in `Docs/Schema/` (or equivalent) so later phases can reference the frozen contract.

Deliverables
- A markdown summary of the schema surface and behavioral notes checked into docs.
- New integration test cases (and fixtures) that assert JSON output and error payloads.
- Test utilities for reusing serialized results across migration phases.

Dependencies
- Existing CLI behavior acts as the baseline; no external packages required.

Risks & Mitigations
- Risk: brittle fixtures that break with unrelated changes. Mitigation: keep sample projects minimal and reuse existing fixtures.
- Risk: missing hidden CLI flags/queries. Mitigation: collaborate with CLI owners to confirm the full surface and add coverage tests where absent.
