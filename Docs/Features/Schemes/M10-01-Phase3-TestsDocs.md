# M10-01 — Phase 3: Schemes Tests & Docs

Goal: Add tests and user docs for scheme introspection.

## Tests

- Fixture via XcodeGen with two schemes:
  - App scheme: builds App+Lib, tests AppTests, runs App
  - CI scheme: builds App+Lib+Tool, tests AppTests+UITests
- Assertions:
  - `schemes { name buildTargets { name } testTargets { name } runTarget { name } }`
  - Filters by `name` and `includesTarget`.

## Docs

- Readme examples for `schemes` queries.
- Release notes entry under Unreleased.

## Acceptance Criteria

- Tests pass and examples reflect actual schema names and fields.

