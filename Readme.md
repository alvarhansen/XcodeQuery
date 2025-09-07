# Xcode Query

Xcode Query (xcq) uses a GraphQL-style query language for predictable, composable queries against your Xcode project. Results are JSON and shaped by your selection set.

## Install via Homebrew

- Stable (once a version is tagged and formula updated):
  - `brew install https://raw.githubusercontent.com/alvarhansen/XcodeQuery/main/HomebrewFormula/xcq.rb`

- HEAD (latest on main):
  - `brew install --HEAD https://raw.githubusercontent.com/alvarhansen/XcodeQuery/main/HomebrewFormula/xcq.rb`

- Local checkout (build from source):
  - `brew install --build-from-source --formula ./HomebrewFormula/xcq.rb`

After install, verify: `xcq --help`

## Usage

- Run against the project in the current directory: `xcq '{ targets { name type } }'`
- Or specify a project: `xcq '{ targets { name } }' --project MyApp.xcodeproj`

## Schema Overview

Top-level fields (selection required):
- `targets(type: TargetType, filter: TargetFilter): [Target!]!`
- `target(name: String!): Target`
- `dependencies(name: String!, recursive: Boolean = false, filter: TargetFilter): [Target!]!`
- `dependents(name: String!, recursive: Boolean = false, filter: TargetFilter): [Target!]!`
- Flat views:
  - `targetSources(pathMode: PathMode = FILE_REF, filter: SourceFilter): [TargetSource!]!`
  - `targetResources(pathMode: PathMode = FILE_REF, filter: ResourceFilter): [TargetResource!]!`
  - `targetDependencies(recursive: Boolean = false, filter: TargetFilter): [TargetDependency!]!`
  - `targetBuildScripts(filter: BuildScriptFilter): [TargetBuildScript!]!`
  - `targetMembership(path: String!, pathMode: PathMode = FILE_REF): TargetMembership!`

Types and inputs:
- `type Target { name, type, dependencies(recursive, filter), sources(pathMode, filter), resources(pathMode, filter), buildScripts(filter) }`
- `type BuildScript { name, stage, inputPaths, outputPaths, inputFileListPaths, outputFileListPaths }`
- Views: `TargetSource { target, path }`, `TargetResource { target, path }`, `TargetDependency { target, name, type }`, `TargetBuildScript { target, ... }`, `TargetMembership { path, targets }`
- `enum TargetType { APP, FRAMEWORK, STATIC_LIBRARY, DYNAMIC_LIBRARY, UNIT_TEST, UI_TEST, EXTENSION, BUNDLE, COMMAND_LINE_TOOL, WATCH_APP, WATCH2_APP, TV_APP, OTHER }`
- `enum PathMode { FILE_REF, ABSOLUTE, NORMALIZED }`
- `enum ScriptStage { PRE, POST }`
- Filters:
  - `input TargetFilter { name: StringMatch, type: TargetType }`
  - `input SourceFilter { path: StringMatch, target: StringMatch }`
  - `input ResourceFilter { path: StringMatch, target: StringMatch }`
  - `input BuildScriptFilter { stage: ScriptStage, name: StringMatch, target: StringMatch }`
  - `input StringMatch { eq: String, regex: String, prefix: String, suffix: String, contains: String }`

## Examples

- List targets and types:
  - `xcq '{ targets { name type } }'`

- Unit test targets only:
  - `xcq '{ targets(type: UNIT_TEST) { name } }'`

- Targets with name ending in "Tests":
  - `xcq '{ targets(filter: { name: { suffix: "Tests" } }) { name } }'`

- Dependencies of a target:
  - Direct: `xcq '{ dependencies(name: "App") { name type } }'`
  - Transitive: `xcq '{ dependencies(name: "App", recursive: true) { name } }'`
  - Reverse (who depends on): `xcq '{ dependents(name: "Lib") { name } }'`

- Per-target dependencies (nested):
  - `xcq '{ targets(type: UNIT_TEST) { name dependencies(recursive: true) { name } } }'`

- Sources
  - Nested, normalized Swift only:
    - `xcq '{ targets(type: FRAMEWORK) { name sources(pathMode: NORMALIZED, filter: { path: { regex: "\\.swift$" }}) { path } } }'`
  - Flat, normalized (easy to pipe):
    - `xcq '{ targetSources(pathMode: NORMALIZED) { target path } }'`

- Resources (Copy Bundle Resources)
  - Per-target JSON resources:
    - `xcq '{ targets { name resources(filter: { path: { regex: "\\.json$" }}) { path } } }'`
  - Flat list, exact filename:
    - `xcq '{ targetResources { target path } }' | jq '.targetResources | map(select(.path == "Info.plist"))'`

- Build scripts
  - Nested for frameworks, pre stage:
    - `xcq '{ targets(type: FRAMEWORK) { name buildScripts(filter: { stage: PRE }) { name stage inputPaths } } }'`
  - Flat with stage filter:
    - `xcq '{ targetBuildScripts(filter: { stage: PRE }) { target name stage } }'`

- Target membership for a file
  - `xcq '{ targetMembership(path: "Shared/Shared.swift", pathMode: NORMALIZED) { path targets } }'`

## jq Recipes

- Files used by multiple targets (normalized):
  - `xcq '{ targetSources(pathMode: NORMALIZED) { target path } }' --project MyApp.xcodeproj | jq '.targetSources | group_by(.path) | map(select(length > 1) | { path: .[0].path, targets: map(.target) })'`

- Files not in any target (absolute):
  - `find "$(pwd)" \( -name "*.swift" -o -name "*.m" -o -name "*.mm" -o -name "*.c" -o -name "*.cc" -o -name "*.cpp" \) -not -path "$(pwd)/.build/*" -not -path "$(pwd)/**/*.xcodeproj/*" -print0 | xargs -0 -n1 -I{} sh -c 'xcq "{ targetMembership(path: \"{}\", pathMode: ABSOLUTE) { path targets } }" --project MyApp.xcodeproj' | jq -s '.[].targetMembership | select(.targets | length == 0)'`

## Notes

- Path formatting is explicit via `pathMode` on fields or flat views. No global state.
- Regex uses `NSRegularExpression` and is case‑sensitive.
- Arrays are sorted by sensible defaults (names/paths) unless further ordering is added later.

## Releasing (maintainers)

1) Create a version tag, e.g. `v0.1.0` and push it:
   - `git tag v0.1.0 && git push origin v0.1.0`

2) GitHub Actions will:
   - Build a release binary for macOS
   - Create a GitHub Release and upload `xcq-v0.1.0-macos.zip`

3) Update Homebrew formula for stable installs:
   - Edit `HomebrewFormula/xcq.rb`:
     - Set `url "https://github.com/alvarhansen/XcodeQuery/archive/refs/tags/v0.1.0.tar.gz"`
     - Set `sha256` for that tarball (example to compute):
       - `curl -L https://github.com/alvarhansen/XcodeQuery/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256`
   - Commit and push the formula change on main.

4) Users can then install stable via:
   - `brew install https://raw.githubusercontent.com/alvarhansen/XcodeQuery/main/HomebrewFormula/xcq.rb`

## Homebrew Tap

Once the `alvarhansen/homebrew-xcodequery` tap has the generated formula, users can install via:

- `brew tap alvarhansen/xcodequery`
- `brew install xcq`
