# M10-01 — Phase 1: Schemes Schema Definition

Goal: Add root `schemes` field, types, and filter input.

## Deliverables

- GraphQL runtime additions:
  - `schemes(filter: SchemeFilter): [Scheme!]!`
  - `Scheme`, `SchemeRef` types
  - `SchemeFilter` input
- SchemaCommand renders them via the schema model.

## Acceptance Criteria

- `xcq schema` shows `schemes` and related types/inputs.

