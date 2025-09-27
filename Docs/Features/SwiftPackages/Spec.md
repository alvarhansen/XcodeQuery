# Swift Packages Introspection — Plan & Spec

This feature adds GraphQL-style introspection for Swift Package Manager (SPM) dependencies referenced by an Xcode project. It exposes packages, products, requirements, and which targets consume which products.

## Objectives

- Inspect packages configured in the project: name/identity, repository URL, requirement (exact, range, branch, revision).
- List package products and which targets consume them.
- Provide filters by package name/identity/url and by consumer target/product.
- Keep results deterministic and easy to pipe, with a flat view in addition to nested fields.

Non-goals (initial):
- Parsing Package.swift or resolving versions via `Package.resolved` beyond the project’s declared requirement.
- License metadata or remote network calls.

## UX Overview

- Query packages at the root: `swiftPackages { name identity url requirement { kind value } }`
- See which targets use which products: `swiftPackages { name products { name } consumers { target product } }`
- From a specific target: `target(name: "App") { packageProducts { packageName productName } }`
- Flat view for piping: `targetPackageProducts { target package product }`

## CLI Additions

- None required; feature is query-surface only. Works in both `query` and `interactive` modes.

## Schema & Types

- Root
  - `swiftPackages(filter: SwiftPackageFilter): [SwiftPackage!]!`
- Target additions
  - `packageProducts(filter: PackageProductFilter): [PackageProductUsage!]!`
- Flat view
  - `targetPackageProducts(filter: PackageProductUsageFilter): [PackageProductUsage!]!`

Types
- `type SwiftPackage { name: String! identity: String! url: String, requirement: PackageRequirement!, products: [PackageProduct!]!, consumers: [PackageConsumer!]! }`
- `type PackageRequirement { kind: RequirementKind!, value: String! }`
- `type PackageProduct { name: String!, type: PackageProductType! }`
- `type PackageConsumer { target: String!, product: String! }`
- `type PackageProductUsage { target: String!, packageName: String!, productName: String! }`

Enums
- `enum RequirementKind { EXACT, RANGE, UP_TO_NEXT_MAJOR, UP_TO_NEXT_MINOR, BRANCH, REVISION }`
- `enum PackageProductType { LIBRARY, EXECUTABLE, PLUGIN, OTHER }`

Inputs
- `input SwiftPackageFilter { name: StringMatch, identity: StringMatch, url: StringMatch, product: StringMatch, consumerTarget: StringMatch }`
- `input PackageProductFilter { name: StringMatch }`
- `input PackageProductUsageFilter { target: StringMatch, package: StringMatch, product: StringMatch }`

## Architecture & Components

- Parse from XcodeProj:
  - Packages: `XCRemoteSwiftPackageReference` (name/identity/url/requirement).
  - Product dependencies per target: `XCSwiftPackageProductDependency`.
- Resolvers map package references and build the consumer/product cross-map once per evaluation.
- Path handling not required (no filesystem traversal).

## Testing Strategy

- Fixture: generate a project with at least two packages and multiple products via XcodeGen.
- Tests:
  - Root `swiftPackages` returns expected identities/requirements.
  - `packageProducts` on `Target` lists products consumed by that target.
  - Flat view `targetPackageProducts` sorts deterministically and supports filters.
  - Filters: `name/url/identity`, `consumerTarget`, and product name filters.

## Implementation Tasks

1) Schema types and inputs (GraphQLSwift)
2) Resolver layer for packages/products/consumers
3) Add target field and flat view (usage)
4) Tests (unit + snapshot where useful)
5) Docs/Readme examples + ReleaseNotes

## Milestones & Estimates

- M9-01 (Schema & adapters): 0.5 day
- M9-02 (Resolvers & usage view): 0.5–1 day
- M9-03 (Tests/docs): 0.5 day

## Risks & Mitigations

- Local packages without URL: make `url` optional and rely on identity/name.
- Requirement representation differs across Xcode versions: normalize to enum+value strings.
- Duplicate product names across packages: always include `packageName` when relevant.

## Open Questions

- Should we surface resolved version from `Package.resolved` as an optional field `resolvedVersion`? (defer)

