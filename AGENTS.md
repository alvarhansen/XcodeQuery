# Repository Guidelines

## Project Structure & Module Organization
- Sources: `Sources/`
  - `XcodeQuery`: executable entry; wires CLI to core.
  - `XcodeQueryCLI`: argument parsing and command routing.
  - `XcodeQueryKit`: core query engine (GraphQL‑style) + XcodeProj.
- Tests: `Tests/XcodeQueryKitTests/` (XCTest specs for the core).
- CI: `.github/workflows/` (release + Homebrew tap automation).
- Packaging: `HomebrewFormula/` and `Makefile` helpers.

## Build, Test, and Development Commands
- Build (debug): `make build` or `swift build -c debug`.
- Run tests (debug): `make test` or `swift test -c debug`.
- Build (release): `make release` or `swift build -c release`.
- Locate binary: `make xcq-bin` (prints path) or `.build/debug/xcq`.
- Local Homebrew install: `make brew-local`.

## Coding Style & Naming Conventions
- Language: Swift 6; target macOS 15.
- Indentation: 4 spaces; UTF‑8; trim trailing whitespace.
- Naming: Types/protocols = UpperCamelCase; methods/vars/cases = lowerCamelCase; files match primary type.
- Error handling: prefer `throws`; avoid force‑unwraps.
- Follow Swift API Design Guidelines; no enforced linter.

## Testing Guidelines
- Framework: XCTest via SwiftPM; core tests live in `Tests/XcodeQueryKitTests/*Tests.swift`.
- Naming: functions as `test…()`, e.g. `testParsesTargetsByType()`.
- Focused runs: `swift test --filter XcodeQueryKitTests/testParsesTargetsByType`.
- Keep fixtures minimal and deterministic; add tests for schema, filters, and path modes.

## Commit & Pull Request Guidelines
- Commits: concise, imperative subject (≤72 chars). Examples: `Add target filter by suffix`, `Fix regex match for ~=`.
- PRs: clear description, small scope; link issues; include CLI examples and update `Readme.md` when schema/flags change.
- Checks: ensure `swift build` and `swift test` pass on macOS; keep `Makefile` targets working.

## Security & Release Notes
- Do not commit secrets; workflows rely on `GITHUB_TOKEN` only.
- Releases: tag `vX.Y.Z`; CI uploads macOS zip and updates the tap. If packaging changes, update `.github/workflows/*` accordingly.

