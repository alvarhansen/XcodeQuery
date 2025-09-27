# M9-01 — Phase 1: Schema Definition for Swift Packages

Goal: Introduce schema surface for packages, products, and requirement types. No resolver logic yet.

## Deliverables

- GraphQLSwift types/enums/inputs for:
  - `SwiftPackage`, `PackageRequirement`, `PackageProduct`, `PackageConsumer`, `PackageProductUsage`.
  - `RequirementKind`, `PackageProductType` enums.
  - Filters: `SwiftPackageFilter`, `PackageProductFilter`, `PackageProductUsageFilter`.
- Root field `swiftPackages(...)` and target field `packageProducts(...)` and flat view `targetPackageProducts(...)` added to schema.
- SchemaCommand renders these in the model (via `XQSchemaBuilder`).

## Acceptance Criteria

- `xcq schema` output includes the new types, inputs, and enums in deterministic order.
- Tests asserting presence of the new types and fields pass.

## Notes

- Align naming and casing with existing schema style.
- Keep defaults and non-null markers consistent with current patterns.

