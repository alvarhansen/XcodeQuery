# M1-03 — InteractiveSession engine (raw-mode, debounce, render)

Goal
- Implement the terminal interactive session engine with single-line editing, debounced evaluation, and live pretty JSON preview.

Requirements
- New type: `InteractiveSession` in `Sources/XcodeQueryCLI/`.
- Works only on TTY; Non-TTY is covered separately (M1-04).
- Single-line input buffer with minimal editing:
  - Insert characters at cursor, Left/Right arrows, Backspace.
  - Ctrl+U clears the line; ESC or Ctrl+C exits.
- Debounce: start an evaluation `Task` after no typing for N ms (`--debounce`), cancel any in-flight evaluation on new keystrokes.
- Rendering:
  - Maintain a preview area above the prompt using ANSI control sequences (save/restore cursor, move, clear).
  - Always pretty-print JSON results (no compact mode).
  - Show parse or execution errors concisely; colorize errors/hints if color is enabled.
- Terminal state is restored on exit (even on error) via `termios` + `defer`.

Instructions
- Raw mode:
  - Use `tcgetattr`/`tcsetattr` to disable canonical mode and echo; restore on exit.
  - Read input byte-by-byte; handle ANSI escape sequences for arrows.
- Buffer + Cursor:
  - Keep a `String` buffer and an integer cursor index; update on key events.
- Debounced evaluation:
  - Hold `var currentEval: Task<Void, Never>?` and a `revision` counter.
  - On schedule, capture the current `buffer` + `revision`, call `session.evaluate(query:)` (from M1-01), then if still latest, render the result.
- Rendering helpers:
  - A small color helper like in `SchemaCommand` to style errors (not JSON).
  - Clear only the preview area between renders; keep the input line intact.
- Exit behavior:
  - ESC or Ctrl+C exits with code 0; ensure terminal is restored.

Acceptance Criteria
- On a TTY, typing a valid query (e.g., `targets { name }`) renders a pretty-printed JSON result in the preview area within ~200ms after pausing typing.
- Typing an invalid/incomplete query renders a parse error without crashing.
- Continuing to type cancels the previous evaluation (no flicker with out-of-order renders).
- Exiting via ESC or Ctrl+C restores the terminal (no lingering raw mode).

Out of Scope
- Multiline editing (M3).
- Autocomplete (M4).

Testing Notes
- Automated tests for TTY raw mode are tricky; rely on Non-TTY tests (M1-04) and manual QA for TTY behavior.
- Add a manual QA checklist in the PR description covering editing, debounce, errors, and exit behavior.
