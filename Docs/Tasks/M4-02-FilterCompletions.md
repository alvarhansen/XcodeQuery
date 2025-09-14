# M4-02 — Autocomplete for Filters (Target/Source/Resource/BuildScript)

Goal
- Provide context-aware completions inside filter arguments and nested StringMatch objects, driven by the static schema model.

Scope
- Filters: `TargetFilter`, `SourceFilter`, `ResourceFilter`, `BuildScriptFilter`.
- Nested input object: `StringMatch` (`eq`, `regex`, `prefix`, `suffix`, `contains`).
- Value suggestions where types are enums (e.g., `TargetType`, `ScriptStage`).

Non-goals (this task)
- Snippet insertion (e.g., auto-inserting `: { }`) or colon/brace management.
- Regex/value completions for string-typed fields (we will not suggest string values).
- Auto-open suggestions while typing (we keep Tab-triggered behavior as currently).

Instructions
1) Extend CompletionProvider context model
- Add input-object awareness to the scanner:
  - Track when the cursor is inside an argument whose type is an input object (e.g., `filter:`), including nested levels (e.g., `name: { ... }`).
  - Maintain a stack of frames for input objects: `{ inputName: String, fields: [XQArgument], usedKeys: Set<String> }`.
  - Maintain the current property (key) where a `:` has been seen but value is not completed yet (to enable enum value suggestions).

2) Build lookups from schema
- Create `inputsByName: [String: XQInputObjectType]` in `CompletionProvider`.
- Reuse existing `typesByName` and enum list.
- Helper: `underlyingInputType(_ ref: XQSTypeRef) -> XQInputObjectType?` returning input type if the type ref points to an input (named or within a list).

3) Update token scanner
- While walking tokens up to (row, col):
  - When encountering a field `ident` followed by `(`, push an argument frame for that field (already implemented); enrich it with input-type info for its args.
  - When encountering `ident` and then `{` within an input context, push a nested input frame based on the selected property's input type (e.g., `name` → `StringMatch`).
  - On `}` or `)` pop the corresponding frame.
  - On `ident :` within an input context, record the property as `lastColonKey` within the top input frame and mark it as used.

4) Suggestion rules
- If inside an input object and immediately within its braces at an identifier position:
  - Suggest remaining keys (schema fields minus `usedKeys`), filtered by the current prefix.
- If inside an input object and after a colon for a property whose type is an enum:
  - Suggest enum cases matching the prefix.
- If inside a nested `StringMatch` input (either directly as the value of a filter key or via `{ path: { ... } }`):
  - Suggest `eq`, `regex`, `prefix`, `suffix`, `contains` (deduped by used keys, prefixed match).
- Otherwise, fallback to existing contexts (root fields, selection fields, argument names).

5) Replace range behavior
- Keep the current replacement strategy: replace the identifier under the cursor only (no colon/braces insertion).
- Do not quote or auto-insert spaces; leave user text intact aside from the identifier.

6) UI interaction (unchanged)
- Tab opens the suggestions; Tab again closes it.
- Up/Down navigate; Right/Enter accept; ESC exits interactive mode.

Acceptance Criteria
- In `targets(filter: { <cursor> })`, pressing Tab shows `name`, `type` and excludes any keys already typed in the object. Selecting inserts only the key text.
- In `targetBuildScripts(filter: { <cursor> })`, pressing Tab shows `stage`, `name`, `target`.
- In `targets(filter: { name: { <cursor> }})`, pressing Tab shows `eq`, `regex`, `prefix`, `suffix`, `contains`.
- In `targets(filter: { type: <cursor> })`, pressing Tab shows `TargetType` enum symbols (e.g., `FRAMEWORK`, `APP`, …).
- In `targetBuildScripts(filter: { stage: <cursor> })`, pressing Tab shows `PRE`, `POST`.
- Outside of input objects, existing suggestions continue to work (root fields, selection fields, argument names, enum values).
- No crashes on malformed/incomplete filter syntax; suggestions may be empty in ambiguous states.

Testing Notes
- Add unit tests for `CompletionProvider.suggest` that feed synthetic buffers and cursor positions to assert returned items:
  - Root filter keys inside each filter input.
  - Nested `StringMatch` keys after opening `{`.
  - Enum values for `TargetFilter.type` and `BuildScriptFilter.stage`.
- Keep tests pure (no TTY). Place under `Tests/XcodeQueryKitTests/` and import `XcodeQueryCLI` to reference `CompletionProvider`.

Implementation Tips
- Reuse and extend the existing tokenizer (ident, braces, parens, colon, comma, string). You do not need a full parser.
- When encountering `{` after a known filter key, resolve that key’s input type to `StringMatch` and push a nested frame.
- Be conservative on error handling: if context is unclear, return nil suggestions rather than guessing.

Out of Scope (future tasks)
- Snippet insertion for `{ }` blocks and `: ` on accept.
- Auto-open suggestions when cursor is inside filter-object contexts.
- Fuzzy matching or ranking across contexts.
