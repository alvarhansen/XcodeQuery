# GraphQL Runtime Schema Guide

This project uses an internal GraphQL-style runtime to define a standards-compliant schema that mirrors the frozen baseline contract.

Where
- Schema builder: `Sources/XcodeQueryKit/XQGraphQLSchema.swift` (Phase 1)
- Frozen baseline: `Docs/Schema/Baseline.md`

Conventions
- Keep type and field names aligned with the baseline doc. Do not introduce new fields/args during migration phases.
- Use `GraphQLNonNull` and `GraphQLList(GraphQLNonNull(...))` to reflect non-null list semantics (e.g., `[String!]!`).
- Provide default values via `GraphQLArgument(..., defaultValue: Map(false))` or `GraphQLArgument(..., defaultValue: Map("FILE_REF"))` to match today’s defaults.

Extending the schema
- Add new enum/value/input/object definitions alongside existing ones.
- Update the `Query` root with new fields and include clear argument types and defaults.
- Add tests in `Tests/XcodeQueryKitTests/*` that assert the schema shape and any new arguments or defaults.

Execution
- The runtime executes queries via the internal executor; resolvers live in `Sources/XcodeQueryKit/XQResolvers.swift`.
