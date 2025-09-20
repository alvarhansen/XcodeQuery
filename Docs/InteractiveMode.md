# XcodeQuery Interactive Mode — Plan & Spec

This document proposes and specifies an Interactive Mode for `xcq` that evaluates queries continuously as you type. It also lays foundations for future multiline input and autocomplete.

## Objectives

- Provide a fast, responsive interactive workflow to explore Xcode projects using the existing GraphQL-style query language.
- Evaluate the current buffer on each change and render output immediately if the query parses and executes successfully.
- Keep the design modular so that future autocomplete can plug into the same editing/session pipeline.
- Reuse a single loaded `XcodeProj` instance for performance; support cancellation and debouncing to avoid overwork while typing.

Non-goals (initial version):
- Full-screen TUI framework; we will implement minimal raw-mode editing and a simple preview panel.
- Networked or multi-project sessions.

## UX Overview

- Launch via a dedicated subcommand: `xcq interactive` (alias: `xcq i`).
- Terminal UI presents:
  - A single-line (later multi-line) input prompt at the bottom.
  - A live preview/output area above the prompt.
  - On every keystroke, debounce (e.g., 150–250ms) and re-run the query; if valid, render results; if invalid, show a concise parse error.
- Results render as pretty-printed JSON (always; no format option).
  - ESC/Ctrl+C quits; Ctrl+U clears line; Left/Right arrows move cursor; Return inserts newline when multi-line mode is added.
- Colorized errors and subtle dim hints when the buffer is incomplete (e.g., trailing comma or missing selection set).

Future UX (autocomplete):
- Tab to cycle suggestions; arrow keys to navigate; accept with Enter/Right.
- Context-aware completions for fields, arguments, enum symbols, and nested selections.

## CLI Additions

New subcommand in `XcodeQueryCLI`:

```
xcq interactive [--project PATH] [--debounce MS] [--color|--no-color]
```

- `--project PATH`: same resolution logic as other commands; optional if a `.xcodeproj` is in CWD.
- `--debounce MS`: integer milliseconds (default 200) between last keystroke and evaluation.
- `--color|--no-color`: same behavior as `schema` command (env overrides supported).

Aliases: `interactive` → `i`.

## Architecture & Components

1) InteractiveCommand (CLI)
- New file: `Sources/XcodeQueryCLI/InteractiveCommand.swift` that wires args, resolves project path, and starts an interactive session.

2) InteractiveSession (CLI)
- New type handling terminal I/O, input buffer, debounced evaluation, cancellation, and rendering.
- Responsibilities:
  - Enter and restore raw terminal mode (termios); handle arrow keys, backspace, Ctrl+C, Ctrl+U.
  - Maintain a text buffer and cursor position (initially single-line; designed for multi-line extension).
  - Debounce input changes and trigger evaluation tasks.
  - Cancel in-flight evaluation if a new keystroke arrives.
  - Render output region using ANSI control sequences (save/restore cursor, clear to end, reposition).
  - On exit, restore terminal state even on error (defer blocks).

3) XcodeProjectQuerySession (Kit)
- New type in `XcodeQueryKit` that encapsulates a single loaded `XcodeProj` and GraphQL-backed engine (GraphQLSwift) for repeated, fast evaluations.
- API sketch:
  - `init(projectPath: String) throws` loads `XcodeProj` once.
  - `func evaluate(query: String) throws -> AnyEncodable` (same semantics as today but reuses the in-memory project).
  - Optionally an `actor` wrapper to serialize access if we find thread-safety issues in `XcodeProj`.
- This avoids reloading the `.xcodeproj` for each keystroke, enabling sub-100ms evaluations for small queries.

4) Schema Introspection Surface (Kit)
- Use the GraphQLSwift runtime schema as the source of truth, adapted into a lightweight model via `XQSchemaBuilder`:
  - Top-level fields, their arguments (name, type, defaults), and return types.
  - Nested fields for object types (Target, Source, Resource, BuildScript, etc.).
- Goals:
  - Drive both `SchemaCommand` rendering and autocomplete from a single source of truth (the runtime schema).
  - Keep the adapter small and deterministic; no runtime reflection beyond GraphQLSwift’s types.

## Evaluation Pipeline (InteractiveSession)

- Keystroke → buffer change → schedule evaluation with debounce timer.
- When the debounce fires:
  - If buffer is empty: clear preview and show a hint (e.g., “Type a selection: targets { name }”).
  - Attempt parse + execute via `XcodeProjectQuerySession.evaluate(query:)`.
  - If parse error: show concise parse error (message + caret position if available) in the preview area.
  - If exec error: show concise execution error.
  - If success: pretty-print JSON; truncate very large arrays with a note (e.g., `…truncated; run 'xcq query' for full output`).
- Concurrency:
  - Maintain a `Task<Void, Never>?` representing the in-flight eval.
  - Before starting a new eval, cancel the previous task.
  - Guard against interleaving by capturing a monotonically increasing revision and only rendering the latest.

## Rendering & Terminal Control

- Minimal, dependency-free terminal handling using ANSI:
  - Save cursor position at the input line; move up to the preview area; clear it; print new output; restore cursor to input.
  - Use `isatty()` to enable live UI only on TTY; if not a TTY, fall back to a simple line-by-line REPL.
- Coloring mirrors `SchemaCommand` approach with a tiny `C` helper struct.
- Respect `--no-color` and `--color`, and `FORCE_COLOR`/`XCQ_FORCE_COLOR` env.

## Autocomplete (Future — M4)

Planned but not in the initial milestone:
- `CompletionProvider` that consumes the schema model and current buffer/cursor to propose candidates.
- Tokenization strategy:
  - Lightweight lexer for identifiers, punctuation, and strings (tokenization consistent with the current GraphQL grammar).
  - Context inference to offer field names where a selection is expected, argument names inside `(...)`, and enum symbols for known args.
- Editor bindings:
  - Tab to request completions; Up/Down to navigate; Enter/Right to accept; Esc to dismiss.
- Nice-to-have: snippet insertion for nested selections (e.g., picking `targets` inserts `{ name type }`).

## Testing Strategy

- `XcodeQueryKit`:
  - Add tests for `XcodeProjectQuerySession` to verify reuse across multiple evaluations returns consistent results and improves performance (coarse checks).
  - Test the schema adapter (`XQSchemaBuilder`) separately from rendering.
- `XcodeQueryCLI`:
  - Add non-TTY REPL tests (line-by-line mode) to cover basic flow without requiring a true terminal.
  - Verify `--debounce`, `--format`, and color flags parsing.
- Manual QA for TTY behavior: verify raw-mode editing, cancellation, and rendering on macOS Terminal/iTerm.

## Implementation Tasks

1. Core session for reuse
- Add `XcodeProjectQuerySession` in Kit; refactor `XcodeProjectQuery` to optionally use it or keep both APIs.

2. Schema source of truth (M2)
- Add a minimal schema description (enums/structs) in Kit; migrate `SchemaCommand` to render from it.

3. CLI subcommand
- Implement `InteractiveCommand` in CLI with flags (`--project`, `--debounce`, `--format`, `--color|--no-color`).
- Wire into `XcodeQueryMainCommand` subcommands list.

4. Interactive session engine (M1)
- Implement `InteractiveSession` with:
  - Raw-mode terminal setup/teardown (termios).
  - Input buffer + minimal line editing (Left/Right/Backspace/Ctrl+U/Ctrl+C).
  - Debounced, cancellable evaluation via Swift concurrency.
  - ANSI-based preview rendering with color/error handling.

5. Fallback non-TTY mode (M1)
- If `!isatty(STDIN/STDOUT)`, run a simple read–eval–print loop using `readLine()` and print results only on Enter.

6. Docs & examples
- Update `Readme.md` with an “Interactive mode” section and examples.

7. Tests (M1/M2)
- Add unit tests as described; integrate into `make test` and CI.

## Milestones & Estimates

- M1 (Interactive, single-line, pretty JSON only): 1–2 days
  - Query session reuse, subcommand, raw-mode input, debounce/cancel, preview rendering, non-TTY fallback.
- M2 (Schema unification): 0.5–1 day
  - Extract schema model; migrate `schema` rendering to use it.
- M3 (Multiline input): 0.5–1 day
  - Buffer supports multiple lines; editor navigation; clean rendering.
- M4 (Autocomplete foundations): 1–2 days
  - Completion provider, simple top-level field/arg completions, Tab to accept.

## Risks & Mitigations

- Terminal handling edge cases (window resize, different emulators): keep rendering simple; test in common terminals; handle SIGWINCH later if needed.
- Performance on large projects: reuse a single `XcodeProj`; add debounce; consider a soft cap on output size (with hint to switch to compact JSON).
- Thread-safety of `XcodeProj`: run evaluations serially via an `actor` or a serial queue if needed.
- Parser friendliness: incomplete buffers will parse as errors frequently; implement friendly messages and detect “possibly incomplete” states heuristically (e.g., unmatched `{`/`(`).

## Open Questions

- Should we prefer a subcommand name `repl` instead of `interactive`? (Spec uses `interactive`; we can add `repl` as an alias too.)
- Do we want a pretty, human table mode for common queries in interactive preview, or keep JSON-only?
- Multiline input priority: ship in M1 or defer to M3 alongside autocomplete?
