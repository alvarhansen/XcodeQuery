# M12-01 — Phase 1: Info.plist Schema Definition

Goal: Add `infoPlist` field to `Target` and types for common keys and entries.

## Deliverables

- GraphQL runtime additions:
  - `InfoPlist`, `InfoPlistEntry` types
  - `InfoPlistKeyFilter` input
  - Target field `infoPlist(configuration: String, filter: InfoPlistFilter): InfoPlist!`
- Update schema model to include these.

## Acceptance Criteria

- `xcq schema` shows the new field and types.

