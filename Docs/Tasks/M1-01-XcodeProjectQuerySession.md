# M1-01 — XcodeProjectQuerySession (core reuse)

Goal
- Add a reusable session type in XcodeQueryKit that loads an Xcode project once and evaluates multiple queries quickly.

Background
- `QueryCommand` uses `XcodeProjectQuery`, which reloads the XcodeProj per invocation. Interactive mode needs sub-100ms loops without reloading.

Requirements
- Add `XcodeProjectQuerySession` in `Sources/XcodeQueryKit/`.
- Always produce pretty-printed JSON via `AnyEncodable` (same as existing `XcodeProjectQuery.evaluate`).
- Preserve existing `XcodeProjectQuery` API and behavior (no breaking changes).

Instructions
- Implement a new type (class or actor):
  - `init(projectPath: String) throws` — loads `XcodeProj` once and stores `projectPath`.
  - `func evaluate(query: String) throws -> AnyEncodable` — trims, rejects leading `{`, parses via `GraphQL`, executes via a single `GraphQLExecutor` constructed with the loaded project and stored path, returns `AnyEncodable`.
- Consider making it an `actor` to serialize access if you observe thread-safety issues; otherwise a class is fine for M1.
- Do not change `GraphQL`, `GraphQLExecutor`, or existing query semantics.

Acceptance Criteria
- A small driver (or tests in M1-06) can instantiate `XcodeProjectQuerySession`, call `evaluate` 2+ times with different queries, and both results are correct and consistent with `XcodeProjectQuery.evaluate`.
- No force-unwraps; errors are thrown for invalid input as per current behavior.
- No breaking changes to public APIs used by existing commands and tests.

Out of Scope
- Automatic reload on project file changes.
- Cross-project caching.

Testing Notes
- Add unit tests in `Tests/XcodeQueryKitTests/` that:
  - Generate a tiny project via XcodeGen (see existing tests) and compare outputs between `XcodeProjectQuery.evaluate` and the new session’s `evaluate`.
  - Call the session `evaluate` multiple times to ensure reuse works (no functional regression).

Coding Guidelines
- Swift 6; macOS 15 target; 4-space indentation; trim trailing whitespace; avoid force-unwraps.
