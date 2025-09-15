# M5-01 — Smarter Editing: Balance + Indent

Goal
- Make interactive editing smoother and clearer by:
  - Auto-indenting new lines according to brace/paren depth.
  - Showing a live, unobtrusive “unbalanced” hint when `{`/`}` or `(`/`)` are not balanced.
  - Gating evaluation while unbalanced to reduce noisy parse errors.
  - When a balanced parse fails, showing a caret (^) at the error column beneath a minimal error line.

Scope
- Applies to TTY interactive mode only.
- Indentation and balance for GraphQL-style input (identifiers, strings, `{}`, `()`, commas, colons).
- Strings and escapes are respected (e.g., `"{"` does not affect balance).

Out of Scope (for this task)
- Auto-inserting matching braces/parens.
- Multi-caret or selection editing.
- Auto-formatting or reflowing entire queries.

UX Requirements
- Auto-indent:
  - Pressing Enter inserts a newline with indentation based on the current syntactic depth.
  - Indent width: 2 spaces per depth level.
  - If the line starts with a closing `}` or `)`, the new line’s indent level is one less (classic outdent).
  - Smart backspace at line start: when the caret is within leading spaces, Backspace jumps back to the previous indent stop (multiples of 2).

- Balance indicator:
  - When the buffer is not balanced, show a dim, single-line hint above the input: e.g., `Unbalanced (3)`.
  - Optionally include a short breakdown (not mandatory in this task), e.g., `Unbalanced {+2, (+1)`.
  - While unbalanced, do not schedule evaluation; clearing previous preview is acceptable.

- Parse error caret:
  - When balanced but parsing fails, render:
    - One-line error message (trimmed, concise), then
    - A second line with a caret `^` under the error column.
  - The caret line is aligned to the error column, taking the current multi-line buffer and window scroll into account.
  - The caret line is shown in the preview region (above input), not inside the input lines.

Technical Requirements
- Tokenizer (InteractiveSession):
  - Scan the entire current buffer on input changes to compute depth and balance.
  - Count `{`/`}` and `(`/`)`, ignoring characters inside string literals and respecting escapes in strings (`\\` and `\"`).
  - Provide helpers:
    - `func computeIndentForNewLine(beforeRow: Int, col: Int) -> Int` → returns number of spaces for the next line.
    - `func computeBalance(_ text: String) -> (balanced: Bool, depthCurlies: Int, depthParens: Int)`

- Indentation behavior:
  - `insertNewline()` should call `computeIndentForNewLine` and insert the appropriate leading spaces.
  - Smart backspace at the start of a line should remove up to previous indent stop (0, 2, 4, ...), not the whole line, unless the line is empty.

- Gating evaluation:
  - In the interactive debounce loop, skip scheduling evaluation when `balanced == false`.
  - If previously shown preview exists, it can remain until the user balances the input, or be cleared.

- Parse error caret position:
  - Change `GQLParser` to propagate a structured position on parse failures (byte or character index):
    - e.g., `GQLError.parseAt(position: Int, message: String)`; keep the existing string-based error for compatibility where needed.
  - In `InteractiveSession`, map `position` to `(row, col)` by walking the current buffer (before scheduling render):
    - Row = count of `\n` before position
    - Col = position since last `\n` (number of scalar characters)
  - Render the caret under the column if the error row is within the current input window; otherwise, render a truncated indicator like `...` followed by caret alignment.

Tests
- Add pure unit tests (no TTY) under `Tests/XcodeQueryKitTests/`:
  1) Balance computation
     - Given strings with various `{}`, `()`, and strings, assert `balanced` and depths.
  2) Indent computation
     - Given contexts like `targets {\n  name`, pressing Enter should return indent level 2; lines starting with `}` should outdent by one level.
  3) Smart backspace
     - Given a line indented by 6 spaces, backspace at col=6 should jump to col=4; at col=1 → col=0.
  4) Parser position mapping
     - Expose (via internal test-only API) a function that maps a position to (row, col), and assert correctness for multiline buffers.
  5) Caret rendering (logic-only)
     - Provide a small formatter that, given a line and column, returns a caret string with proper spaces; assert alignment for several columns.

Acceptance Criteria
- Auto-indent:
  - Pressing Enter after an opening `{` or `(` increases indentation by 2 spaces; after a closing `}` or `)`, the new line is outdented by 2 spaces.
  - Smart backspace at line start removes indentation to the previous 2-space stop.

- Balance indicator & gating:
  - While unbalanced, the preview area shows a dim `Unbalanced (N)` hint and no evaluation runs (no new preview). Once balanced, evaluation resumes on next debounce.

- Parse error caret:
  - With a balanced but invalid query, the preview shows an error line and a caret line aligned under the error column. The caret column corresponds to the reported parser position.

- Compatibility:
  - Existing interactive features (multiline, suggestions, bottom pinning) continue to work. No crashes when typing malformed input; behavior degrades gracefully to the unbalanced hint.

Implementation Notes
- For performance, the balance/indent scan is O(n) over the current buffer and is cheap compared to evaluation; run it on each keypress before scheduling evaluation.
- Keep the caret line short by trimming or eliding left content if the column is far right (e.g., replace leading spaces with `…` then spaces).
- Do not modify evaluation semantics beyond gating on `balanced == false`.

Future Extensions (not required here)
- Auto-insert matching `}`/`)` when accepting fields that require selection.
- Optional configurable indent width.
- Optional mode to always show parse caret (even when unbalanced), with best-effort guess.
