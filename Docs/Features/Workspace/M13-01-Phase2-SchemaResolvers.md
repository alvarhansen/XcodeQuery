# M13-01 — Phase 2: Schema and Resolvers for Workspace Projects

Goal: Add `projects` root field and implement workspace scheme inclusion.

## Tasks

1) Schema additions
   - `type Project { name: String!, path: String!, targets: [Target!]! }`
   - `projects: [Project!]!` root field.

2) Resolvers
   - Build `Project` objects from loaded workspace contexts.
   - For `schemes` root field, if workspace is loaded, include schemes from workspace `xcshareddata`.

3) Sorting
   - Sort projects by `name`, then `path`.
   - Targets under a project sorted by `name`.

## Acceptance Criteria

- `projects { name path targets { name } }` returns expected values for a fixture with two projects.
- `schemes` includes workspace schemes when in workspace mode.

