# M6-01 Phase 1 — GraphQLSwift Schema Definition Layer

Goal
- Introduce GraphQLSwift to the build and model the schema types so GraphQLSwift can represent the existing query contract.

Context
- GraphQLSwift brings a standards-compliant schema builder; we must mirror our frozen baseline using its APIs without altering runtime behavior yet.

Tasks
- Add the `GraphQL` package dependency in `Package.swift` and regenerate `Package.resolved`.
- Create schema builder code (objects, enums, input objects) that reflect the Phase 0 inventory, including documentation for fields/arguments.
- Establish mappings from existing domain models (`Target`, `Source`, etc.) to GraphQLSwift output types.
- Add focused schema tests confirming every root field and argument defined in Phase 0 exists in the new schema.
- Update developer docs to explain how to extend the schema using GraphQLSwift.

Deliverables
- Updated SwiftPM manifests referencing GraphQLSwift.
- New schema definition files under `Sources/XcodeQueryKit/` (or a dedicated module) backed by unit tests.
- CI/build verification that the new dependency compiles on macOS 15.

Dependencies
- Relies on the Phase 0 schema inventory and golden tests as the authoritative contract.

Risks & Mitigations
- Risk: GraphQLSwift API mismatches our data structures. Mitigation: prototype schema fragments in isolation and document any required type adapters.
- Risk: Dependency integration issues (e.g., transitive conflicts). Mitigation: pin versions explicitly and validate with `swift build`/`swift test` on CI.
