# M9-01 — Phase 2: Resolvers and Filters for Swift Packages

Goal: Implement GraphQL resolvers to back the new schema using XcodeProj, including filters and deterministic sorting.

## Tasks

1) Build in-memory index
   - Enumerate `XCRemoteSwiftPackageReference` for package metadata.
   - For each `PBXNativeTarget`, collect `XCSwiftPackageProductDependency` → product usage.
   - Build maps:
     - `packageByIdentity`
     - `productsByPackage[package] = [productName]`
     - `consumers[(package, product)] = Set(targets)`

2) Root resolver `swiftPackages`
   - Return `SwiftPackage` objects with `name/identity/url/requirement` populated.
   - Resolve `products` and `consumers` from the maps.
   - Apply `SwiftPackageFilter` (name/identity/url/product/consumerTarget) via existing `StringMatch` helpers.
   - Sort by `identity`, then `name`.

3) `Target.packageProducts`
   - For a given target, list `PackageProductUsage { packageName, productName }`.
   - Support `PackageProductFilter` on product name.
   - Sort by `packageName`, then `productName`.

4) Flat view `targetPackageProducts`
   - Emit rows `(target, package, product)` across all targets.
   - Support `PackageProductUsageFilter` on target/package/product.
   - Sort by `target`, then `package`, then `product`.

## Acceptance Criteria

- Queries return expected rows with stable ordering for a fixture with 2+ packages and 3+ targets.
- Filters behave consistently with other inputs (prefix/suffix/contains/regex).

## Risks

- Targets may not have any package products; ensure empty arrays are returned, not null.
- Local packages: missing URL is acceptable (url nullable).

