# M6-01 Phase 1 — GraphQL runtime Schema Definition Layer

Status
- Completed with the internal runtime schema implementation (2026-02-01).

Goal
- Define internal GraphQL runtime schema types that mirror the existing query contract.

Context
- The internal runtime exposes schema builder APIs; we must mirror our frozen baseline using these APIs without altering behavior.

Tasks
- Create schema builder code (objects, enums, input objects) that reflect the Phase 0 inventory, including documentation for fields/arguments.
- Establish mappings from existing domain models (`Target`, `Source`, etc.) to GraphQL runtime output types.
- Add focused schema tests confirming every root field and argument defined in Phase 0 exists in the new schema.
- Update developer docs to explain how to extend the schema using GraphQL runtime.

Deliverables
- New schema definition files under `Sources/XcodeQueryKit/` backed by unit tests.
- CI/build verification that the internal runtime compiles on macOS 15.

Dependencies
- Relies on the Phase 0 schema inventory and golden tests as the authoritative contract.

Risks & Mitigations
- Risk: GraphQL runtime API mismatches our data structures. Mitigation: prototype schema fragments in isolation and document any required type adapters.
- Risk: Schema drift over time. Mitigation: keep schema tests aligned with `Docs/Schema/Baseline.md`.
