# M7-01 — Drive SchemaCommand from GraphQLSwift Schema

Context
- Today, `SchemaCommand` renders from a static model `XcodeQuerySchema.schema` (Kit) and pretty-prints it (CLI).
- We also define the executable GraphQL schema in `XQGraphQLSwiftSchema.makeSchema()` (Kit) for query execution.
- Maintaining both introduces duplication and drift risk. It’s acceptable for the CLI output to change slightly if it enables a cleaner, reusable pipeline.

Goals
- Use the GraphQLSwift schema as the single source of truth for the `schema` command.
- Remove ad‑hoc duplication across the static schema and GraphQLSwift runtime schema.
- Produce a reusable in‑memory model suitable for both rendering and interactive completions.

Approach
1) Add adapter: GraphQLSwift → XQSchema
   - Implement `XQSchemaBuilder.from(graphQL: GraphQLSchema) -> XQSchema` in `XcodeQueryKit`.
   - Traverse the GraphQLSwift `GraphQLSchema` returned by `XQGraphQLSwiftSchema.makeSchema()` and build:
     - `topLevel`: fields on the `Query` root as `[XQField]` with arguments + defaults and return types.
     - `types`: all object types except `Query` as `[XQObjectType]` with their fields and args.
     - `inputs`: all `GraphQLInputObjectType`s as `[XQInputObjectType]`.
     - `enums`: all `GraphQLEnumType`s as `[XQEnumType]`.
   - Type mapping rules to `XQSTypeRef`:
     - `GraphQLNonNull(T)` → set nonNull on the outer `XQSTypeRef` (named or list).
     - `GraphQLList(T)` → `.list(of: ...)`, set `elementNonNull` if `T` is `GraphQLNonNull(Named)`.
     - Named scalars/objects/enums → `.named("Name", nonNull: …)`.
   - Defaults formatting:
     - Boolean: `true|false` (unquoted)
     - Enums: symbol name (e.g., `FILE_REF`, unquoted)
     - Strings: quoted (e.g., `"App"`), escape inner quotes

2) Migrate SchemaCommand to the adapter
   - Build the GraphQL schema at runtime with `XQGraphQLSwiftSchema.makeSchema()`.
   - Convert once via `XQSchemaBuilder` and feed the result to the existing renderer in `renderSchemaFromModel`.
   - Keep coloring and section layout; accept minor ordering/formatting changes where needed for deterministic, clean logic.
   - Optional safety lever: support `XCQ_SCHEMA_SOURCE=static` to render from `XcodeQuerySchema.schema` for emergency fallback during rollout.

3) Deterministic ordering
   - GraphQLSwift field collections may not guarantee insertion order. For stable output:
     - Sort top‑level fields by name unless we explicitly impose a curated order.
     - Sort `types`, `inputs`, and `enums` by name.
     - Sort fields and input fields by name within each type.
   - This will change the printed order slightly vs. today; it’s acceptable per the goal of cleaner reusable logic.

4) Completions (follow‑up)
   - Leave `CompletionProvider` defaulted to `XcodeQuerySchema.schema` initially to minimize blast radius.
   - After validating the adapter, consider injecting the adapter‑built schema into interactive mode so completions and `schema` render share one source of truth.

Deliverables
- `XQSchemaBuilder.swift` in Kit with GraphQLSwift→XQSchema conversion.
- `SchemaCommand` updated to build from GraphQLSwift via the adapter (with optional static fallback via env var).
- Deterministic sorting in the adapter to stabilize output.

Tests
- Adapter unit tests:
  - Build GraphQL schema → adapt → assert presence/structure of key entities (top‑level field names, argument names/types/defaults, object fields, inputs, enums). Compare after sorting to avoid order brittleness.
  - Focused checks for default values: `recursive: false`, `pathMode: FILE_REF`, string defaults.
- Schema rendering test:
  - Validate color/section anchors still exist (e.g., contains "Top-level fields", "Types:", "Enums:").
  - Accept ordering differences; do not snapshot exact full text.

Acceptance Criteria
- `swift build` and `swift test` pass on macOS.
- `xcq schema` prints from GraphQLSwift via the adapter with stable, sorted sections.
- Output remains readable and complete; minor ordering differences are acceptable.

Rollout
1. Land adapter + optional fallback env.
2. Switch `SchemaCommand` default to GraphQLSwift adapter.
3. Observe in CI; if stable, remove `XcodeQuerySchema.swift` and update `CompletionProvider` to consume the adapted schema.

Risks & Mitigations
- Ordering differences may surprise users scanning output → document the new alphabetical ordering; keep section grouping identical.
- Default value formatting parity → explicit tests for booleans/enums/strings.
- Runtime cost of building schema for `schema` command is small and one‑shot → acceptable for a CLI help command.
