# GraphQL Migration Options (CLI + WASM)

Date: 2026-02-01

## Context (from `Docs/Research/GraphQLNeeds.md`)
The CLI currently depends on a GraphQL runtime that provides:
- Parsing selection-set queries (no top-level braces).
- Schema definition + introspection for `schema` and autocomplete.
- Execution against resolvers with error behavior validated by tests.
- Stable JSON encoding shape.

Any migration must preserve these behaviors and error strings (see `GraphQLNeeds.md`).

## Option A — SociableWeaver

### What it is
SociableWeaver is a **declarative GraphQL query builder**. The README describes it as a lightweight framework that makes GraphQL queries look natural in Swift, using Swift function builders and `CodingKeys` to avoid stringly-typed queries. It focuses on building query strings and includes features like arguments, fragments, variables, directives, mutations, inline fragments, and meta fields (from the Table of Contents). citeturn3view0

From the Swift Package Index:
- No package dependencies.
- Last updated April 24, 2023. citeturn1view0

### Fit vs. XcodeQuery needs
**Pros**
- Pure Swift, no dependencies. citeturn1view0
- Declarative API could help **construct** queries for tests or for a future UI. citeturn3view0

**Gaps (critical)**
- **No execution/runtime**: the README only discusses *building* GraphQL queries; it does not describe parsing or executing queries against a schema. (Inference based on README scope.) citeturn3view0
- **No schema/introspection model** for `schema` output or autocomplete (not described in README). (Inference.) citeturn3view0
- **Maintenance staleness**: last SPI update is 2023. citeturn1view0

### Conclusion for A
SociableWeaver is a **query-construction DSL**, not a server-side runtime. It does **not** cover the core needs of XcodeQuery (parsing + execution + schema introspection). Adopting it would still require building a custom runtime — so it does not reduce the migration scope.

## Option B — Build a minimal runtime inspired by the previous external GraphQL library

### Reference baseline
The prior external GraphQL library used in this repo provided a full schema model and executor, closely mirroring the GraphQL JS reference implementation. That library has now been removed in favor of the internal runtime.

### Minimal runtime scope (aligned to our needs)
A custom runtime could narrow the surface to exactly what XcodeQuery uses:
- **Parser**: selection-only documents, input objects, enums, strings, optional commas.
- **Schema model**: objects, fields, args, enums, input objects, list/non-null wrappers.
- **Executor**: synchronous resolver graph, deterministic error strings, and JSON value output.
- **Introspection model** for schema + autocomplete (could reuse existing `XQSchema` model).

This would likely be smaller than the previous external library, and can be built to avoid NIO/Dispatch for WASM.

### Pros
- **WASM-friendly** (no NIO/Dispatch required).
- **Size + dependency control**.
- **Deterministic error strings** matching existing tests.
- Easier to **enforce selection-only** constraint.

### Cons / Risks
- **Engineering effort**: even minimal parsing/validation/execution is non-trivial.
- **Bug surface**: must match existing query behavior and error strings in tests.
- **Maintenance burden**: custom runtime becomes long-term internal dependency.

## Recommendation Summary
- **Option A (SociableWeaver)** is **not sufficient** for a CLI runtime migration. It only helps build query strings and would still require building a parser/executor/schema model. (Inference.) citeturn3view0
- **Option B (custom minimal runtime)** is the only path that can fully satisfy WASM constraints while preserving the CLI contract, but it has higher implementation cost.

## Suggested Next Steps
1. Decide whether **WASM is a hard requirement** for the CLI runtime or only for the web demo.
2. If WASM is required, draft a **minimal grammar + executor spec** matching `GraphQLNeeds.md`.
3. If WASM is not required for CLI, consider keeping a full-featured runtime for CLI and building a **separate wasm-only runtime** to reduce risk.
