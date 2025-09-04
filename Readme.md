# Xcode Query

## Install via Homebrew

- Stable (once a version is tagged and formula updated):
  - `brew install https://raw.githubusercontent.com/alvarhansen/XcodeQuery/main/HomebrewFormula/xq.rb`

- HEAD (latest on main):
  - `brew install --HEAD https://raw.githubusercontent.com/alvarhansen/XcodeQuery/main/HomebrewFormula/xq.rb`

- Local checkout (build from source):
  - `brew install --build-from-source --formula ./HomebrewFormula/xq.rb`

After install, verify: `xq --help`

## Query Language

- Targets list:
  - `xq '.targets'`
  - `xq '.targets[] | filter(.type == .unitTest)'`
  - `xq '.targets[] | filter(.name.hasSuffix("Tests"))'`
  - `xq '.targets[] | filter(.name | hasSuffix("Tests"))'`

- Enriched per-target stages (default after ops):
  - `.targets[] | sources` → `[{ name, type, sources: [String] }]`
  - `.targets[] | resources` → `[{ name, type, resources: [String] }]`
  - `.targets[] | dependencies` → `[{ name, type, dependencies: [{name,type}] }]`
  - `.targets[] | buildScripts` → `[{ name, type, buildScripts: [{ name?, stage, inputPaths, …}] }]`

- Bracket selectors for nested filtering (AND/OR in one filter):
  - Paths/names/types: `.sources[].path`, `.resources[].path`, `.dependencies[].name`, `.dependencies[].type`, `.buildScripts[].name`, `.buildScripts[].stage`
  - Example:
    - `xq '.targets[] | sources(pathMode: "normalized") | dependencies | filter(.sources[].path ~= "\\.swift$" && .dependencies[].name == "Lib")'`

- Flatten when you need flat output:
  - `... | flatten(.sources)` → `[{ target, path }]`
  - `... | flatten(.resources)` → `[{ target, path }]`
  - `... | flatten(.dependencies)` → `[{ target, name, type }]`
  - `... | flatten(.buildScripts)` → `[{ target, …script fields… }]`

### Reverse dependencies and dependency queries

- Direct deps of a target: `xq '.dependencies("App")'`
- Transitive deps of a target: `xq '.dependencies("App", recursive: true)'`
- Reverse deps (who depends on): `xq '.dependents("Lib")'`
- Reverse deps alias: `xq '.reverseDependencies("Lib")'` or `xq '.rdeps("Lib")'`
- Pipeline (enriched): `xq '.targets[] | filter(.type == .unitTest) | dependencies(recursive: true)'`
  - Use bracket selectors to filter by dependency fields:
  - `xq '.targets[] | dependencies | filter(.dependencies[].name ~= "^App$")'`

### Source files

- Direct call (flat): `xq '.sources("App")'`
- Pipeline (enriched): `xq '.targets[] | filter(.type == .framework) | sources'`
  - Filter nested with brackets: `xq '.targets[] | sources | filter(.sources[].path ~= "\\.swift$")'`
  - Get flat list: `xq '.targets[] | sources | flatten(.sources)'`

Notes

- Direct calls like `.sources("App")` return file reference paths by default. See Path options below.

### Target membership

- Targets for a file: `xq '.targetMembership("Shared/Shared.swift")'`
- With path mode: `xq '.targetMembership("Shared/Shared.swift", pathMode: "normalized")'`
- Pipeline: `xq '.targets[] | sources(pathMode: "normalized") | targetMembership'` (returns each file with the targets it belongs to)

### jq examples

- Files used by multiple targets (normalized paths):
  - `xq '.targets[] | sources(pathMode: "normalized") | targetMembership' --project MyApp.xcodeproj | jq -r '.[] | select(.targets | length > 1) | "\(.path) -> \(.targets|join(", "))"'`

- Files not in any target (absolute paths):
  - `find "$(pwd)" \( -name "*.swift" -o -name "*.m" -o -name "*.mm" -o -name "*.c" -o -name "*.cc" -o -name "*.cpp" \) -not -path "$(pwd)/.build/*" -not -path "$(pwd)/**/*.xcodeproj/*" -print0 | xargs -0 -n1 -I{} sh -c 'xq ".targetMembership(\"{}\", pathMode: \"absolute\")" --project MyApp.xcodeproj' | jq -s '. | map(select(.targets | length == 0))'`

### Path options

- Control path formatting for `sources`, `resources`, and `targetMembership` via `pathMode`:
  - Absolute paths: `xq '.sources("App", pathMode: "absolute")'`
  - Normalized to project root: `xq '.sources("App", pathMode: "normalized")'`
  - Pipeline variant: `xq '.targets[] | filter(.type == .framework) | sources(pathMode: "normalized") | targetMembership'`
- Modes:
  - `fileRef`: raw `PBXFileReference.path`/`name` (default)
  - `absolute`: fully-resolved absolute path
  - `normalized`: relative to project root

### Build script queries

- Per-target scripts: `xq '.buildScripts("App")'`
- Pipeline (enriched): `xq '.targets[] | filter(.type == .framework) | buildScripts'`
- Filter nested with brackets:
  - Stage: `xq '.targets[] | buildScripts | filter(.buildScripts[].stage == .pre)'`
  - Name prefix: `xq '.targets[] | buildScripts | filter(.buildScripts[].name ~= "^Pre")'`
- Flat list of scripts: `xq '.targets[] | buildScripts | flatten(.buildScripts)'`

### Resources (Copy Bundle Resources)

- Per-target resources: `xq '.resources("App")'`
- With path mode: `xq '.resources("App", pathMode: "normalized")'`
- Pipeline (enriched): `xq '.targets[] | resources'`
- Filter nested with brackets:
  - Exact filename: `xq '.targets[] | resources | filter(.resources[].path == "Info.plist")'`
  - Regex (JSON files): `xq '.targets[] | resources | filter(.resources[].path ~= "\\.json$")'`
- Flat list of resources: `xq '.targets[] | resources | flatten(.resources)'`

## Compatibility

- Direct function calls remain flat to support one-offs and scripting:
  - `.sources("App")`, `.resources("App")`, `.buildScripts("App")`, `.dependencies("App")`
- Pipelines starting with `.targets[]` enrich target objects by default; use bracket selectors to filter nested arrays and `flatten(...)` when you need flat results.

## Regex and equality

- Equality `==` is literal.
- Regex `~=` is case-sensitive and uses `NSRegularExpression`.
  - Example: `.resources[].path ~= "\\.json$"`

## Releasing (maintainers)

1) Create a version tag, e.g. `v0.1.0` and push it:
   - `git tag v0.1.0 && git push origin v0.1.0`

2) GitHub Actions will:
   - Build a release binary for macOS
   - Create a GitHub Release and upload `xq-v0.1.0-macos.zip`

3) Update Homebrew formula for stable installs:
   - Edit `HomebrewFormula/xq.rb`:
     - Set `url "https://github.com/alvarhansen/XcodeQuery/archive/refs/tags/v0.1.0.tar.gz"`
     - Set `sha256` for that tarball (example to compute):
       - `curl -L https://github.com/alvarhansen/XcodeQuery/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256`
   - Commit and push the formula change on main.

4) Users can then install stable via:
   - `brew install https://raw.githubusercontent.com/alvarhansen/XcodeQuery/main/HomebrewFormula/xq.rb`

## Homebrew Tap

Once the `alvarhansen/homebrew-xcodequery` tap has the generated formula, users can install via:

- `brew tap alvarhansen/xcodequery`
- `brew install xq`