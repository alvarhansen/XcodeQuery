# M14-01 — Migrate Interactive CLI to TauTUI

Goal
- Replace the custom raw-terminal interactive engine with TauTUI while preserving the current user-facing interactive behavior.

Why
- Reduce maintenance cost for terminal input/rendering.
- Reuse TauTUI primitives for editor, rendering, and event handling.
- Keep XcodeQuery focused on query semantics and completions instead of terminal internals.

Scope
- `xcq interactive` and alias `xcq i` in TTY mode.
- Keep Non-TTY behavior unchanged.
- Keep debounce evaluation, live preview, multiline editing, and GraphQL-aware completions.

Out of Scope (this task)
- Reworking query engine semantics.
- New interactive commands or slash-command system.
- Replacing the existing completion model with a new schema system.

Migration Plan
1. Baseline Integration
- Add TauTUI package dependency and create `TauInteractiveSession`.
- Wire interactive commands to use Tau session in TTY mode.
- Keep old `InteractiveSession` temporarily as rollback path during migration.

2. Lifecycle and Concurrency Hardening
- Remove custom run loop control from async context.
- Use explicit start/stop lifecycle with continuation-based wait until exit.
- Ensure evaluation tasks are cancellable and revision-gated.
- Keep all UI mutations on `MainActor`.

3. Feature Parity Restoration
- Reconnect GraphQL completion provider to Tau editor completion hooks.
- Preserve insertion behavior (`field`, `field { }`, `field: { }`) using existing `CompletionProvider` logic.
- Keep unbalanced-input hint and debounce gating.

4. Validation and Cleanup
- Build and test (`swift build`, `swift test`).
- Validate manual interactive flows (TTY): edit, multiline, completion, cancel, Ctrl+C/ESC exit.
- Remove legacy `InteractiveSession` after parity is confirmed and fallback is no longer needed.

Risks
- TauTUI public API gaps can block custom completion adapters.
- Actor isolation violations are easy to introduce with detached evaluation tasks.
- Terminal behaviors can differ across emulators; exit and key handling must be verified.

Mitigations
- If TauTUI lacks required public API, add minimal public surface upstream (path dependency in local workspace).
- Keep a narrow session wrapper that isolates concurrency and task cancellation.
- Validate on at least one terminal with Option+Enter and ESC/Ctrl+C behavior.

Acceptance Criteria
- `xcq interactive` and `xcq i` run with TauTUI in TTY mode.
- Non-TTY mode remains line-oriented and unchanged.
- Live preview updates with debounce and shows unbalanced hint.
- GraphQL completions work with existing insertion behavior.
- ESC and Ctrl+C both exit interactive mode cleanly.
- `swift build -c debug` succeeds; tests remain green.

Implementation Notes
- Keep the migration incremental: compile-first, then parity, then cleanup.
- Prefer minimal TauTUI surface changes over local workarounds.
