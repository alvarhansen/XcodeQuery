# M2-01 — Static Schema Model (single source of truth)

Goal
- Introduce a lightweight, static schema description in `XcodeQueryKit` to describe top-level fields, types, and arguments used by the query engine.

Requirements
- New Swift file(s) in `Sources/XcodeQueryKit/` defining data structures like `Schema`, `ObjectType`, `Field`, `Argument`, `EnumType`.
- Encode the current resolvable surface:
  - Top-level fields: `targets`, `target`, `dependencies`, `dependents`, `targetSources`, `targetResources`, `targetDependencies`, `targetBuildScripts`, `targetMembership`.
  - Object types: `Target`, `Source`, `Resource`, `BuildScript`, etc., with their fields.
  - Enums and argument types (e.g., `TargetType`, `PathMode`, `BuildScriptFilter` shape, simple filter objects).
- Do not change runtime execution; this is descriptive only.

Instructions
- Create a static instance `XcodeQuerySchema.schema` describing the entities above.
- Keep the model simple and typed (no reflection). Nesting/child fields can be arrays on the type definition.
- Add doc comments to explain each top-level field, its args, and return type.

Acceptance Criteria
- A unit test can import `XcodeQueryKit` and access `XcodeQuerySchema.schema` to enumerate top-level fields and find their arguments/types.
- The schema covers all fields displayed by `SchemaCommand` today.

Out of Scope
- Generating code or validations from the schema.
- Parser changes.
