# M4-01 — Autocomplete Foundations for Interactive Mode

Goal
- Provide basic, schema-driven autocomplete suggestions in interactive mode.

Requirements
- Use the static schema (M2) to power completions:
  - Top-level field names.
  - Object fields inside selection sets.
  - Argument names inside `(...)`.
  - Enum symbols for known enum arguments (e.g., `TargetType`, `PathMode`).
- Editor bindings:
  - Press Tab to request/show suggestions.
  - Up/Down to navigate suggestions; Enter/Right to accept; Esc to dismiss.
- Rendering:
  - Show a compact suggestions panel above the input or inline one line above.

Instructions
- Add a lightweight tokenizer to identify the token at cursor position (ident/string/enum/punctuator).
- Compute context from surrounding tokens to determine suggestion set (top-level field vs argument vs nested field).
- Insert accepted completion text into the buffer, respecting cursor position.

Acceptance Criteria
- On a TTY, typing `tar` at the start and pressing Tab shows `targets`/`target` suggestions; accepting inserts the full identifier.
- Inside `targets(`, pressing Tab shows argument names like `type` and `filter`.
- For `type: ` position, Tab shows enum symbols (e.g., `FRAMEWORK`).
- No crashes with invalid/incomplete buffers.

Out of Scope
- Fuzzy scoring or ranking; exact prefix matching is sufficient.
- Snippet generation beyond simple identifier insertion.
