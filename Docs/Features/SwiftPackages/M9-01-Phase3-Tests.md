# M9-01 — Phase 3: Tests for Swift Packages Introspection

Goal: Add XCTest coverage for schema presence, resolver correctness, filters, and ordering.

## Test Matrix

- Schema presence
  - Assert `XQSchemaBuilder.fromGraphQLSwift()` includes new types/inputs/enums.
- Integration fixture (XcodeGen)
  - Project with two packages: A (library product ACore), B (library product BUI and executable BTool).
  - Targets: App uses ACore+BUI; Tool uses BTool; Tests uses ACore only.
- Root queries
  - `swiftPackages { identity requirement { kind value } }` returns 2 packages.
  - Filter by `name`, `identity`, `url`, and `product`.
  - `consumers { target product }` contains expected pairs.
- Target field
  - `target(name: "App") { packageProducts { packageName productName } }` lists ACore+BUI.
- Flat view
  - `targetPackageProducts { target package product }` deterministic ordering and filter by `target`.

## Acceptance Criteria

- New tests pass on CI and locally via `make test`.

