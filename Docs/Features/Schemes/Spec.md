# Schemes & Actions Introspection — Plan & Spec

Expose Xcode schemes and their actions to understand build/test/run topology across a project (and later a workspace).

## Objectives

- List available schemes with build/test/run information.
- Identify which targets are built and tested by each scheme.
- Provide filters by scheme name and by included target names.

Non-goals (initial):
- Executing schemes or deriving environment variables; introspection only.
- Full test plan details or test configurations beyond target lists.

## UX Overview

- List schemes: `schemes { name isShared buildTargets { name } testTargets { name } runTarget { name } }`
- Filter by name: `schemes(filter: { name: { prefix: "App" } }) { name }`
- Filter schemes that include a target: `schemes(filter: { includesTarget: { eq: "App" } }) { name }`

## CLI Additions

- None for project-level. Workspace support is covered in the Workspace feature.

## Schema & Types

- Root
  - `schemes(filter: SchemeFilter): [Scheme!]!`

Types
- `type Scheme { name: String!, isShared: Boolean!, buildTargets: [SchemeRef!]!, testTargets: [SchemeRef!]!, runTarget: SchemeRef }`
- `type SchemeRef { name: String! }`

Inputs
- `input SchemeFilter { name: StringMatch, includesTarget: StringMatch }`

## Architecture & Components

- Parse `.xcscheme` files using XcodeProj `XCScheme` APIs:
  - Read shared schemes from `xcshareddata` and optionally user schemes (defer for now).
  - Extract BuildAction/RunAction/TestAction target references and resolve to names.
- Resolvers project-wide; later extended to workspace-level.

## Testing Strategy

- Fixture with custom shared schemes (via XcodeGen) that include different sets of targets.
- Validate sorting by scheme name, and inclusion lists per action.
- Filters:
  - `name` prefix/suffix/regex
  - `includesTarget` contains a specific target

## Implementation Tasks

1) Schema types/inputs for schemes and `SchemeRef`
2) Resolver to enumerate schemes, extract actions and map target names
3) Filters and deterministic sort
4) Tests and examples; docs and release notes

## Milestones & Estimates

- M10-01 (Schema): 0.25 day
- M10-02 (Resolvers/filters): 0.75 day
- M10-03 (Tests/docs): 0.5 day

## Risks & Mitigations

- User schemes live under `xcuserdata` and may not be portable; default to shared schemes only; consider opt-in later.
- Projects without schemes (edge); return empty array.

## Open Questions

- Do we want to expose configurations per action (Debug/Release) now or later?

