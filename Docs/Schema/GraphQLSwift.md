# GraphQLSwift Schema Guide

This project uses the GraphQLSwift `GraphQL` package to define a standards-compliant schema that mirrors the frozen baseline contract.

Where
- Schema builder: `Sources/XcodeQueryKit/GraphQLSwiftSchema.swift` (Phase 1)
- Frozen baseline: `Docs/Schema/Baseline.md`

Conventions
- Keep type and field names aligned with the baseline doc. Do not introduce new fields/args during migration phases.
- Use `GraphQLNonNull` and `GraphQLList(GraphQLNonNull(...))` to reflect non-null list semantics (e.g., `[String!]!`).
- Provide default values via `GraphQLArgument(..., defaultValue: .boolean(false))` or `.enumValue("FILE_REF")` to match today’s defaults.

Extending the schema (post‑migration)
- Add new enum/value/input/object definitions alongside existing ones.
- Update the `Query` root with new fields and include clear argument types and defaults.
- Add tests in `Tests/XcodeQueryKitTests/*` that assert the schema shape and any new arguments or defaults.

Execution
- Phase 1 models the schema only. Resolvers are introduced in later phases (see Phase 2 and Phase 3 docs) while keeping output parity with legacy execution.

