# M9-02 - GraphQL Runtime (WASM-Friendly)

Status
- Completed with the internal runtime implementation (2026-02-01).

Goal
- Implement a minimal internal GraphQL-style runtime that preserves CLI behavior and works in WASM.

Deliverables
- New runtime module in `Sources/XcodeQueryKit/GraphQLRuntime/*`:
  - Value model (`Map`) with helpers.
  - Type system (`GraphQLSchema`, `GraphQLObjectType`, `GraphQLInputObjectType`, `GraphQLEnumType`, `GraphQLTypeReference`, etc.).
  - Parser for selection-only queries.
  - Executor + validation with required error strings.
- Migration of schema/resolvers to new types (replace external GraphQL library usage).
- Updated `XQSchemaBuilder` to consume the internal schema model.
- Updated CLI and tests to use the new runtime.
- Remove external GraphQL + NIO dependencies from Package.swift.

Acceptance Criteria
- `swift test -c debug` passes locally on macOS.
- `xcq query` and `xcq interactive` behave identically for baseline queries.
- `xcq schema` and autocomplete use the new schema model.
- All GraphQL baseline snapshots remain unchanged.

Notes
- Preserve selection-only input requirement.
- Keep error messages aligned with `Docs/Schema/Baseline.md` and tests.
