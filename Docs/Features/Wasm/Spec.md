# XcodeQuery WASM + Web Demo

Goal
- Make the XcodeQuery query engine usable from WASM and provide a browser demo for running GraphQL-style queries against `.xcodeproj` bundles.

Scope (initial)
- Export a small C ABI for query execution:
  - `xcq_alloc`, `xcq_free`, `xcq_last_error`.
  - `xcq_query_from_pbxproj_json(data, len, query, len, projectPath, len)`.
- Parse `project.pbxproj` bytes in WASM and execute selection-only queries via the internal GraphQL runtime.
- Provide a static web UI that:
  - Accepts a dropped `.xcodeproj` folder or zip.
  - Extracts `project.pbxproj`.
  - Sends query + pbxproj bytes to the WASM module.
  - Displays JSON output + errors.
- Provide `make wasm-web` (Docker-based) to build `web/xcodequery-wasm.wasm`.

Non-goals (initial)
- Full filesystem-backed parsing (no reading of source files).
- Workspace support.
- Shared schemes or user data (will be empty in WASM unless added later).

Behavioral Requirements
- Query behavior and error strings match CLI output.
- Deterministic JSON output (pretty-printed; sorted keys optional).
- Clear error reporting via `xcq_last_error` when execution fails.

WASM Requirements
- No dependency on Dispatch or NIO.
- Pure Swift + Foundation + XcodeProj fork with WASI support.
- Exported functions stable for the web harness.

Follow-ups
- Optional: scheme support by passing `.xcscheme` data or enabling directory enumeration in the XcodeProj fork for WASI.
- Optional: persistent project handle to avoid re-parsing pbxproj between queries.
