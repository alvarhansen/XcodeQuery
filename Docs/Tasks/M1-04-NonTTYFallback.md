# M1-04 — Non-TTY fallback (line-by-line REPL)

Goal
- Provide a simple Non-TTY mode for `xcq interactive` that reads queries line-by-line and prints pretty JSON results.

Requirements
- Triggered when either stdin or stdout is not a TTY.
- Behavior:
  - Read a line via `readLine()` repeatedly until EOF.
  - Skip empty lines; for non-empty lines, evaluate and print the pretty JSON result followed by a newline.
  - On parse or execution error, print a concise error message to stderr; continue reading next line.
  - Exit on EOF with code 0.
- Colorization is disabled in Non-TTY mode by default; do not color JSON.

Instructions
- Implement a small loop (likely within `InteractiveCommand.run()` or a helper) that accepts a `XcodeProjectQuerySession` and streams lines.
- Use `JSONEncoder` with `.prettyPrinted` for output; do not support compact formatting.
- Ensure this path shares the same evaluation code as TTY mode (no duplication).

Acceptance Criteria
- CLI integration test can pipe a single line query into `xcq interactive --project <proj>` and receive a pretty-printed JSON object on stdout with no ANSI escapes.
- Invalid input produces a single-line error to stderr and the process remains alive to accept the next line (when provided), exiting cleanly on EOF.

Out of Scope
- Complex prompts or stateful history in Non-TTY.

Testing Notes
- Add an integration test in `Tests/XcodeQueryKitTests/CLIIntegrationTests.swift` that:
  - Generates a sample project (like existing tests).
  - Runs `xcq interactive --project <proj>` with stdin set to `"targets { name }\n"`.
  - Asserts that stdout parses as JSON and contains the `targets` key.
