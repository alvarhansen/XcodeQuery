# M1-06 — Tests for Interactive Mode Foundation

Goal
- Add tests that validate the reusable query session and the Non-TTY interactive pathway.

Requirements
- Tests go under `Tests/XcodeQueryKitTests/`.
- Cover two areas:
  1) Core session reuse: `XcodeProjectQuerySession` returns results consistent with `XcodeProjectQuery.evaluate`.
  2) Non-TTY interactive: piping a line into `xcq interactive` yields pretty JSON on stdout.

Instructions
- Use the existing XcodeGen-based fixture strategy from current tests to create a tiny project with at least 2 targets and a dependency.
- Session reuse test:
  - Instantiate `XcodeProjectQuerySession` with the generated project.
  - Evaluate `targets { name type }` and `targets(type: FRAMEWORK) { name }`.
  - Compare decoded outputs with those from `XcodeProjectQuery(projectPath:).evaluate(...)`.
- Non-TTY test:
  - Locate the built `xcq` binary (use `Self.locateXCQBinary()` pattern from existing tests).
  - Run `xcq interactive --project <proj>` with stdin set to `"targets { name }\n"`.
  - Assert exit status 0 and that stdout parses as JSON with the `targets` key.

Acceptance Criteria
- `swift test -c debug` passes locally (on macOS) with the new tests added and existing tests intact.
- Tests are deterministic and do not rely on network access.

Out of Scope
- TTY/raw-mode automation (manual QA only for M1-03).
