# M2-02 — Migrate SchemaCommand to use Static Schema

Goal
- Render the schema help from the new static schema model instead of ad-hoc string assembly, keeping output and colors consistent.

Requirements
- Update `Sources/XcodeQueryCLI/SchemaCommand.swift` to build its output by traversing `XcodeQuerySchema.schema` (added in M2-01).
- Preserve current coloring behavior and formatting as closely as possible to avoid breaking existing tests.
- Keep `SchemaCommand.__test_renderSchema(useColor:)` as a test hook.

Instructions
- Introduce small render helpers that map schema entities to lines (types, fields, examples).
- Ensure environment/flag behavior for color remains identical.

Acceptance Criteria
- `swift test` passes, including `SchemaColorTests` and any other golden-output tests.
- Manual check: `xcq schema` output visually matches previous version (color and structure).

Out of Scope
- Extending the schema itself beyond current capabilities.
