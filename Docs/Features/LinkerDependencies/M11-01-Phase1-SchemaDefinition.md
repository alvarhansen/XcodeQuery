# M11-01 — Phase 1: Schema Definition for Linker Inputs

Goal: Add schema for link dependencies at target level and flat view, with filter and enum.

## Deliverables

- GraphQLSwift additions:
  - `LinkKind` enum, `LinkDependency`, `TargetLinkDependency` types
  - `LinkFilter` input
  - Target field `linkDependencies(...)`
  - Root field `targetLinkDependencies(...)`
- SchemaCommand includes the new items via the model adapter.

## Acceptance Criteria

- `xcq schema` lists the new fields/types/enums/inputs.

