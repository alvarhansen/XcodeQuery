# M10-01 — Phase 2: Schemes Resolvers

Goal: Implement resolvers to enumerate schemes and extract build/test/run target references.

## Tasks

1) Enumerate shared schemes: `.xcodeproj/xcshareddata/xcschemes/*.xcscheme`
   - Load via `XcodeProj` `XCScheme`.
   - `isShared = true` for shared; user schemes deferred.

2) Map actions to target names
   - BuildAction: map `buildActionEntries` → target names
   - TestAction: `testables` → target names
   - RunAction: `buildConfiguration` and `runnable` target (if any) → name

3) Filters and sorting
   - `name` StringMatch
   - `includesTarget`: check membership in union of build/test/run lists
   - Sort by `name`

## Acceptance Criteria

- Deterministic scheme listing with accurate action membership for a fixture.

