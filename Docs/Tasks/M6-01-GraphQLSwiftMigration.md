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
1. Inventory Schema Surface
   - Document current query root fields, arguments, nested selections, and enum/input usages.
   - Capture any quirks (e.g. rejection of top-level braces) to consciously handle or revise.
2. Wire Up GraphQLSwift
   - Add the dependency, define schema objects/enums/input types, and stand up the query root using GraphQLSwift’s APIs.
   - Port resolver logic from `GraphQLExecutor`, adapting signatures but keeping data transformations intact.
3. Integrate and Decommission Legacy Parser
   - Replace calls to the old parser with the new GraphQLSwift execution pipeline while preserving the `JSONValue` output structure.
   - Remove or retire the custom parser/AST types once tests and manual verification confirm parity.

Acceptance Criteria
- `swift test` and `swift build` succeed with the new dependency included.
- Existing CLI queries (targets, dependencies, targetSources, etc.) return the same JSON shapes and filtering behavior as before.
- Error messages for invalid queries now originate from GraphQLSwift and are surfaced cleanly to the CLI.
- Legacy parser code is removed or clearly marked for deletion with no remaining call sites.

Out of Scope
- Expanding the query schema beyond the current feature set.
- CLI UX changes unrelated to the parser swap (flags, output formatting, etc.).
