# M6-01 Phase 2 — Resolver Adapter Layer

Goal
- Bridge GraphQLSwift resolver signatures to the existing `GraphQLExecutor` logic so data fetching behavior remains unchanged.

Context
- GraphQLSwift expects resolver closures returning `EventLoopFuture` or synchronous values; our current executor already knows how to hydrate `JSONValue` trees. An adapter layer keeps reuse high while avoiding a big-bang rewrite.

Tasks
- Design adapter types that translate GraphQLSwift resolver inputs (source, arguments, context) into calls on existing executor helpers.
- Implement resolvers for every root field and nested object defined in Phase 0, delegating to current helper functions.
- Ensure output normalization matches the existing JSON serialization that CLI tests assert.
- Add unit tests per resolver exercising success paths, argument decoding, and error propagation.
- Document how to add new resolvers via the adapter so future features remain consistent.

Deliverables
- Adapter/resolver source files in `Sources/XcodeQueryKit/` with coverage across all schema entry points.
- Resolver-focused unit tests verifying data parity with the legacy executor.
- Internal documentation highlighting the mapping between GraphQLSwift types and existing executor components.

Dependencies
- Requires Phase 1 schema objects and Phase 0 golden tests to confirm behavior.

Risks & Mitigations
- Risk: Divergence between GraphQLSwift resolver expectations and our synchronous code. Mitigation: encapsulate async handling in adapters and add thorough test coverage.
- Risk: Overlooked edge cases in argument decoding. Mitigation: borrow fixtures from Phase 0 failure-mode tests and expand them here.
