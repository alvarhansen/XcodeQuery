# Release Notes

## Unreleased

- Schema source of truth
  - SchemaCommand now renders from the GraphQLSwift runtime schema via an adapter (`XQSchemaBuilder`).
  - CompletionProvider also consumes the adapter‑built schema for suggestions.
  - Removed the static schema instance (`XcodeQuerySchema.schema`) and the `XCQ_SCHEMA_SOURCE` fallback env.
  - Output ordering may be slightly different (deterministic alphabetical in sections).

- Decommission legacy GraphQL parser and executor.
  - Removed bespoke parser/AST/executor previously in `Sources/XcodeQueryKit/GraphQL.swift`.
  - CLI no longer supports `--legacy` or `--compare-engines`; GraphQLSwift is the sole engine.
  - Error messages originate from GraphQLSwift; tests adjusted to assert informative substrings.
- Documentation
  - Updated interactive mode and session docs to reference GraphQLSwift exclusively.
  - Cleaned test queries and examples to use valid GraphQL string escaping for regex patterns.
- Migration notes
  - If any tooling referenced internal legacy types (e.g., `GQLError`, `GraphQLExecutor`), migrate to the GraphQLSwift schema and resolvers (`XQGraphQLSwiftSchema`, `XQResolvers`).
  - For regex arguments in queries, ensure patterns are properly escaped for GraphQL strings (e.g., use `"\\.swift$"`).
