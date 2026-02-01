# GraphQL Runtime (WASM-Friendly)

Goal
- Replace the external GraphQL library with an internal, WASM-friendly GraphQL-style runtime.
- Preserve existing CLI behavior, error strings, and JSON output shape.

Scope
- Selection-only queries (no top-level braces).
- Schema definition for objects/enums/inputs/args with non-null and list wrappers.
- Parser for selection sets, arguments, input objects, enums, booleans, strings, numbers, null.
- Synchronous executor with resolver closures.
- Schema model for `schema` command and autocomplete.

Non-goals (initial)
- Mutations, subscriptions, variables, fragments.
- Full GraphQL spec compliance beyond current usage.
- Introspection queries (schema output uses internal model).

Behavioral Requirements
- Error messages must match current tests:
  - Reject top-level braces with the existing message.
  - Selection set required errors include "selection of subfields".
  - Missing required args mention the arg name.
  - Parse errors include "Parse error: <message> @<position>" with messages like "Unterminated string literal", "Expected identifier", "Expected '}'".
- Output JSON must match current snapshots (sorted key tests).

WASM Requirements
- No dependency on Dispatch or NIO.
- Pure Swift + Foundation; use synchronous execution.

Integration Notes
- Update `XQGraphQLSchema` to use the internal runtime types.
- Update `XcodeProjectQuery`, `XcodeProjectQuerySession`, `SchemaCommand`, and `CompletionProvider`.
- Update tests to use the new runtime.
