# M6-01 — Replace Custom GraphQL Parser with GraphQLSwift

Goal
- Migrate query parsing/execution from the bespoke `GQLParser` to the `GraphQL` package maintained by GraphQLSwift while keeping the CLI query surface compatible.

Background
- `Sources/XcodeQueryKit/GraphQL.swift` currently houses a hand-written parser, AST, and executor that directly translate query strings into resolver calls.
- The absence of schema tooling and validation makes it hard to extend queries or deliver good error messages.
- GraphQLSwift offers a standards-compliant parser, validator, and execution engine that we can map onto our existing resolver logic.

Requirements
- Add the `GraphQL` dependency (https://github.com/GraphQLSwift/GraphQL) to `Package.swift` and ensure it builds on macOS 15.
- Define GraphQLSwift schema types for the objects we already expose (`Target`, dependency graphs, source/resource rows, build scripts, etc.) and keep their fields/arguments aligned with today’s CLI contract.
- Implement resolvers that reuse existing logic in `GraphQLExecutor` so responses continue to match current behavior and serialization.
- Provide backwards-compatible parsing entry points for CLI commands (e.g. maintain `GraphQL.parseAndExecute` as a façade that now delegates into GraphQLSwift).
- Update documentation/tests to reflect the new dependency and verify query compatibility (additions to `Tests/XcodeQueryKitTests` as needed).

Implementation Phases
- Phase 0 — Baseline Fidelity Freeze ([Docs/Tasks/M6-01-Phase0-BaselineFidelity.md](M6-01-Phase0-BaselineFidelity.md)): document the existing schema surface, capture edge cases, and lock behavior with golden tests.
- Phase 1 — GraphQLSwift Schema Definition Layer ([Docs/Tasks/M6-01-Phase1-SchemaDefinition.md](M6-01-Phase1-SchemaDefinition.md)): add the GraphQL dependency and model the schema types to mirror today’s contract.
- Phase 2 — Resolver Adapter Layer ([Docs/Tasks/M6-01-Phase2-ResolverAdapters.md](M6-01-Phase2-ResolverAdapters.md)): bridge GraphQLSwift resolver signatures onto the current executor helpers.
- Phase 3 — Dual Execution Harness ([Docs/Tasks/M6-01-Phase3-DualExecution.md](M6-01-Phase3-DualExecution.md)): run legacy and GraphQLSwift pipelines side-by-side behind a feature flag to validate parity and performance.
- Phase 4 — CLI Flip and Fallback Strategy ([Docs/Tasks/M6-01-Phase4-CLISwitch.md](M6-01-Phase4-CLISwitch.md)): make GraphQLSwift the default execution path while keeping a guarded rollback lever.
- Phase 5 — Legacy Parser Decommission ([Docs/Tasks/M6-01-Phase5-LegacyRemoval.md](M6-01-Phase5-LegacyRemoval.md)): remove the bespoke parser once GraphQLSwift has baked in production.

Acceptance Criteria
- `swift test` and `swift build` succeed with the new dependency included.
- Existing CLI queries (targets, dependencies, targetSources, etc.) return the same JSON shapes and filtering behavior as before.
- Error messages for invalid queries now originate from GraphQLSwift and are surfaced cleanly to the CLI.
- Legacy parser code is removed or clearly marked for deletion with no remaining call sites.

Out of Scope
- Expanding the query schema beyond the current feature set.
- CLI UX changes unrelated to the parser swap (flags, output formatting, etc.).
