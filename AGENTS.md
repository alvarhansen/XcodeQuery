# Repository Guidelines

## Project Structure & Module Organization
- Sources: `Sources/`
  - `XcodeQuery` (executable entry, wires CLI to core)
  - `XcodeQueryCLI` (argument parsing and command routing)
  - `XcodeQueryKit` (core GraphQL-style query engine, XcodeProj integration)
- Tests: `Tests/XcodeQueryKitTests/` (XCTest specs for the core)
- CI: `.github/workflows/` (release + Homebrew tap automation)
- Packaging: `HomebrewFormula/` (local install formula), `Makefile` helpers

## Build, Test, and Development Commands
- Build (debug): `make build` or `swift build -c debug`
- Tests (debug): `make test` or `swift test -c debug`
- Build (release): `make release` or `swift build -c release`
- Find built binary: `make xcq-bin` (prints path) or `.build/debug/xcq`
- Local Homebrew install: `make brew-local`

## Coding Style & Naming Conventions
- Language: Swift 6, macOS 15 target.
- Indentation: 4 spaces; trim trailing whitespace; UTF‑8 files.
- Names: Types/protocols = UpperCamelCase; methods/vars/enum cases = lowerCamelCase; files match primary type name.
- Error handling: prefer `throws` over `fatalError`; avoid force‑unwrap.
- Style source: follow Swift API Design Guidelines; no enforced linter in repo.

## Testing Guidelines
- Framework: XCTest via SwiftPM.
- Location: `Tests/XcodeQueryKitTests/*Tests.swift`.
- Naming: test functions `test…()` describing behavior, e.g. `testParsesTargetsByType()`.
- Run focused tests: `swift test --filter XcodeQueryKitTests/testParsesTargetsByType`.
- Add tests for schema changes, filters, and path modes; keep fixtures minimal and deterministic.

## Commit & Pull Request Guidelines
- Commits: concise, imperative subject (≤72 chars). Examples: `Add target filter by suffix`, `Fix regex match for ~=`.
- PRs: clear description, scope small; link issues; include CLI examples and updated `Readme.md` when schema/flags change.
- Checks: ensure `swift build` and `swift test` pass on macOS; keep `Makefile` targets working.

## Security & Release Notes
- Do not commit secrets. Workflows use `GITHUB_TOKEN` only.
- Releases: tag `vX.Y.Z`; CI uploads macOS zip and updates the tap. If you modify release packaging, update `.github/workflows/*` accordingly.
