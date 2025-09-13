# M1-05 — Update Readme with Interactive Mode

Goal
- Document how to use interactive mode with examples and behavior notes.

Requirements
- Add a new section "Interactive Mode" to `Readme.md`.
- Include:
  - Overview of `xcq interactive` (alias `i`).
  - TTY behavior (live preview, debounce, errors in place) and Non-TTY behavior (line-by-line).
  - Note that output is always pretty-printed JSON.
  - Flags: `--project`, `--debounce`, `--color`/`--no-color`.
  - A short example GIF or ASCII snippet (optional) and at least one CLI example users can copy/paste.

Instructions
- Update `Readme.md` without removing existing content; add the new section under the CLI usage area.
- Keep copy concise; defer deep internals to `Docs/InteractiveMode.md`.

Acceptance Criteria
- `Readme.md` contains a clearly labeled “Interactive Mode” section with the items listed above.
- No broken Markdown or code blocks.
