# M1-02 — Add `interactive` subcommand (CLI)

Goal
- Provide a new `xcq interactive` subcommand (alias: `i`) to run interactive mode.

Requirements
- Command lives in `Sources/XcodeQueryCLI/InteractiveCommand.swift`.
- Flags:
  - `--project PATH` (optional): same resolution logic as `QueryCommand`.
  - `--debounce MS` (optional Int, default 200): debounce delay in milliseconds.
  - `--color` / `--no-color`: same behavior and env overrides (`XCQ_FORCE_COLOR`, `FORCE_COLOR`) as in `SchemaCommand`.
- Pretty JSON is always used for rendering results in interactive mode; do not add a `--format` flag.

Instructions
- Implement `InteractiveCommand: AsyncParsableCommand` with `commandName: "interactive"` and alias `i`.
- In `run()`, resolve project path (reuse logic from `QueryCommand`).
- Instantiate `XcodeProjectQuerySession` (from M1-01).
- Detect TTY using `isatty(STDIN_FILENO)` and `isatty(STDOUT_FILENO)`:
  - If both TTY: create and start `InteractiveSession` (see M1-03) with debounce and color settings.
  - Else: run Non-TTY fallback (see M1-04).
- Wire the new command into `XcodeQueryMainCommand` subcommands array.

Acceptance Criteria
- `xcq interactive --help` lists the command, alias `i`, and the three flags above.
- Running `xcq interactive --project <proj>` launches without crashing and exits cleanly on Ctrl+C (in TTY) or EOF (in non-TTY).
- `xcq -h` shows the `interactive` subcommand in the help output.

Out of Scope
- The terminal editor and rendering (handled by M1-03).
- Autocomplete or multiline input.

Testing Notes
- Add a CLI integration test (non-TTY) that feeds a single line query to stdin and asserts pretty-printed JSON output (see M1-04 test guidance).
