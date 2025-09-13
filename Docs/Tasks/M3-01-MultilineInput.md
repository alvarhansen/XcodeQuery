# M3-01 — Multiline Input Support in Interactive Mode

Goal
- Extend `InteractiveSession` to support multiline queries while preserving live evaluation and clean rendering.

Requirements
- Editor behavior changes:
  - Return inserts a newline at the cursor (no immediate exit).
  - Up/Down move within the buffer lines; Left/Right respect line boundaries.
  - Ctrl+U clears the current line; Ctrl+C/ESC exits (same as M1).
- Rendering:
  - Input area expands to show all lines (with a reasonable max height, e.g., 10 lines) and scrolls if needed.
  - Preview area remains above input; reflow the screen on resize as a stretch goal.
- Evaluation:
  - Debounce evaluates the entire buffer (all lines joined by `\n`).

Instructions
- Update buffer data structure to track lines and cursor (row, col).
- Update key handling to support newline, Up/Down, and line edits.
- Adjust rendering to draw N input lines at the bottom; re-render the preview above after clearing the region.

Acceptance Criteria
- On a TTY, pressing Return inserts a newline and the buffer shows multiple lines; evaluation processes the full buffer.
- Cursor navigation works across lines; Backspace joins lines correctly when at column 0.
- Preview updates continue to work and remain responsive.

Out of Scope
- Code folding or advanced navigation.
- Autocomplete (M4).
