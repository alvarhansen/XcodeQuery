# M9-03 — WASM Support + Web Demo

Goal
- Build a WASM-friendly XcodeQuery runtime and a browser demo for running queries against `.xcodeproj` bundles.

Tasks
1. Add a WASM executable target with C ABI exports for query execution.
2. Add a public entrypoint in `XcodeQueryKit` that evaluates a query given `project.pbxproj` data + project path.
3. Add `Dockerfile.wasm` and `Makefile` targets to build the wasm artifact.
4. Add `web/` demo assets modeled after the XcodeProj WASM demo.
5. Document how to build and run the demo locally.

Acceptance Criteria
- `make wasm-web` produces `web/xcodequery-wasm.wasm`.
- The web demo accepts a `.xcodeproj` folder or zip and runs queries.
- Errors are surfaced in the UI with the same error strings as the CLI.

Notes
- Schemes will be empty in WASM until shared-data loading is implemented.
