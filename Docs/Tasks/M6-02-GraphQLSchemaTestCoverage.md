# GraphQL Schema Test Coverage Gaps (to add)

Context: After M6 GraphQLSwift migration, ensure runtime tests exercise all schema cases (both legacy executor and GraphQLSwift resolvers where applicable). Below is a concrete list of missing or lightly covered cases to implement as tests.

## Root Fields
- targets
  - Filter.name operators: eq, prefix, contains (suffix covered via snapshots).
  - GraphQLSwift execution path using `filter` (current tests use only `type`).
- target(name: String!)
  - Basic happy path via GraphQLSwift (baseline covered, Swift path not).
  - Error: unknown target (GraphQLSwift path).
- dependencies(name!, recursive=false, filter)
  - GraphQLSwift root resolver coverage (baseline covered).
  - Recursive=false vs true result difference.
  - Filter by type and by name StringMatch (eq/prefix/suffix/contains).
- dependents(name!, recursive=false, filter)
  - GraphQLSwift root resolver coverage (baseline covered).
  - Recursive=false vs true.
  - Filter by type and by name StringMatch.
- targetSources(pathMode=FILE_REF, filter)
  - PathMode=ABSOLUTE behavior (flat/normalized already covered elsewhere).
  - Filter.path operators: eq, prefix, suffix, regex (contains covered).
  - Filter.target operator use (GraphQLSwift path).
- targetResources(pathMode=FILE_REF, filter)
  - PathMode=ABSOLUTE behavior (flat/normalized covered across tests).
  - Filter.path operators: eq, prefix, suffix, regex (contains covered).
  - Filter.target operator use (GraphQLSwift path).
- targetDependencies(recursive=false, filter)
  - GraphQLSwift root resolver coverage (baseline covered).
  - Recursive=false vs true.
  - Filter by type and name StringMatch.
- targetBuildScripts(filter)
  - GraphQLSwift root resolver coverage (baseline covered via legacy and CLI).
  - Filter.stage=POST (PRE covered); include mixed PRE/POST assertions.
  - Filter by name (StringMatch eq/prefix/suffix/contains) and by target.
- targetMembership(path!, pathMode=FILE_REF)
  - GraphQLSwift coverage of membership lookup.
  - PathMode defaults (FILE_REF) and ABSOLUTE mode.

## Target Nested Fields
- Target.dependencies(recursive=false, filter)
  - GraphQLSwift nested with filter (type and name), and recursive flag.
- Target.sources(pathMode, filter)
  - PathMode=ABSOLUTE; filter.path eq/prefix/suffix/regex.
- Target.resources(pathMode, filter)
  - PathMode=ABSOLUTE; filter.path eq/prefix/suffix/regex.
- Target.buildScripts(filter)
  - Filter.stage (PRE, POST), filter.name/target StringMatch operators; assert stage and I/O paths.

## Filters and Match Operators
- StringMatch operators matrix across fields: eq, regex, prefix, suffix, contains
  - Apply to: TargetFilter.name; SourceFilter.path; ResourceFilter.path; BuildScriptFilter.name; BuildScriptFilter.target; Source/Resource flat filters `target`.
  - Ensure at least one GraphQLSwift-backed test per operator and per filter kind.

## Path Modes
- ABSOLUTE path mode
  - Verify for: targetSources, targetResources (flat and nested), targetMembership.
- FILE_REF default behavior
  - Explicit tests where not already inferred by absence of `pathMode` arg.

## Error Handling (GraphQLSwift)
- target(name: <unknown>) – should error.
- Unknown field in selection set – should error.
- Missing selection set for fields that require it – should error.

## Parity/Snapshot Enhancements
- Add snapshot cases (baseline) for:
  - PathMode=ABSOLUTE on flat resources/sources.
  - targetBuildScripts filter by POST and by name/target.
  - targetDependencies with recursive true/false.

---

Implementation notes:
- Prefer reusing `GraphQLBaselineFixture` for deterministic projects and mirroring patterns in `GraphQLSwiftResolverTests` for GraphQLSwift execution.
- For ABSOLUTE mode checks, assert that returned paths start with the temp project root and resolve symlinks (standardizedFileURL).
- When adding GraphQLSwift error tests, use `graphql(schema:request:context:eventLoopGroup).wait()` and assert `result.data == nil` and `result.errors` non-empty.
