# XcodeQuery

XcodeQuery (`xcq`) is a CLI for querying Xcode projects with a GraphQL-style selection language.
It returns deterministic JSON shaped by your selection set.

## Quick Start

1. Install:
   - `brew tap alvarhansen/xcodequery`
   - `brew install xcq`
2. Run in a project directory containing an `.xcodeproj`:
   - `xcq 'targets { name type }'`
3. Or pass a project path explicitly:
   - `xcq 'targets { name }' --project MyApp.xcodeproj`

Try the WASM demo: <https://blog.hansen.ee/XcodeQuery/web/>

## Install

- Stable binary:
  - `brew tap alvarhansen/xcodequery`
  - `brew install xcq`
- HEAD build:
  - `brew install --HEAD xcq`

Verify:
- `xcq --help`

## Interactive Mode

Start:
- `xcq interactive [--project PATH] [--debounce MS] [--color|--no-color]`
- Alias: `xcq i`

Behavior:
- In TTY, interactive mode uses a TauTUI-based UI with a multiline editor and live preview.
- Query evaluation is debounced (default `200ms`) and preview is always pretty JSON.
- `Enter` inserts newline (Shift/Option/Command+Enter also work).
- `ESC` or `Ctrl+C` exits.
- In non-TTY mode (piped stdin), input is read line-by-line and each line is evaluated.

Completions:
- `Tab` shows suggestions.
- `Up/Down` navigates suggestions.
- `Enter` or `Tab` accepts suggestion.
- Supports top-level fields, nested fields, input keys, and enum values.

## Query Surface

Use `xcq schema` for the full generated schema.

High-value top-level fields:
- Targets and graph:
  - `targets`, `target`, `dependencies`, `dependents`, `targetDependencies`
- Files and membership:
  - `targetSources`, `targetResources`, `targetMembership`
- Build and schemes:
  - `schemes`, `targetBuildScripts`, `buildConfigurations`, `projectBuildSettings`, `targetBuildSettings`
- Linking:
  - `targetLinkDependencies`
- Swift packages:
  - `swiftPackages`, `targetPackageProducts`

Core enums and inputs you will use often:
- Enums: `TargetType`, `PathMode`, `ScriptStage`, `BuildSettingsScope`, `BuildSettingOrigin`, `LinkKind`
- Inputs: `TargetFilter`, `SourceFilter`, `ResourceFilter`, `BuildScriptFilter`, `BuildSettingFilter`, `StringMatch`

## Common Examples

Targets:
- `xcq 'targets { name type }'`
- `xcq 'targets(type: UNIT_TEST) { name }'`
- `xcq 'targets(filter: { name: { suffix: "Tests" } }) { name }'`

Dependencies:
- `xcq 'dependencies(name: "App") { name type }'`
- `xcq 'dependencies(name: "App", recursive: true) { name }'`
- `xcq 'dependents(name: "Lib") { name }'`

Sources and resources:
- `xcq 'targets(type: FRAMEWORK) { name sources(pathMode: NORMALIZED, filter: { path: { regex: "\\.swift$" }}) { path } }'`
- `xcq 'targetSources(pathMode: NORMALIZED) { target path }'`
- `xcq 'targetResources { target path }'`

Build scripts:
- `xcq 'targets(type: FRAMEWORK) { name buildScripts(filter: { stage: PRE }) { name stage inputPaths } }'`
- `xcq 'targetBuildScripts(filter: { stage: PRE }) { target name stage }'`

Schemes:
- `xcq 'schemes { name isShared buildTargets { name } testTargets { name } runTarget { name } }'`
- `xcq 'schemes(filter: { includesTarget: { eq: "App" } }) { name }'`

Build settings:
- `xcq 'buildConfigurations'`
- `xcq 'projectBuildSettings(filter: { key: { prefix: "SWIFT" } }) { configuration key value values isArray }'`
- `xcq 'targetBuildSettings(filter: { configuration: { eq: "Release" }, key: { prefix: "CODE_SIGN" } }) { target configuration key value origin }'`

Swift Packages:
- `xcq 'swiftPackages { name identity url requirement { kind value } }'`
- `xcq 'target(name: "App") { packageProducts { packageName productName } }'`
- `xcq 'targetPackageProducts { target packageName productName }'`

## jq Recipes

Files used by multiple targets:
- `xcq 'targetSources(pathMode: NORMALIZED) { target path }' --project MyApp.xcodeproj | jq '.targetSources | group_by(.path) | map(select(length > 1) | { path: .[0].path, targets: map(.target) })'`

Files not in any target:
- `find "$(pwd)" \( -name "*.swift" -o -name "*.m" -o -name "*.mm" -o -name "*.c" -o -name "*.cc" -o -name "*.cpp" \) -not -path "$(pwd)/.build/*" -not -path "$(pwd)/**/*.xcodeproj/*" -print0 | xargs -0 -n1 -I{} sh -c 'xcq "targetMembership(path: \"{}\", pathMode: ABSOLUTE) { path targets }" --project MyApp.xcodeproj' | jq -s '.[].targetMembership | select(.targets | length == 0)'`

## Notes

- Path output is explicit via `pathMode` (no global path mode state).
- Regex filters use `NSRegularExpression` and are case-sensitive.
- Arrays are sorted by stable defaults unless explicitly stated otherwise.

## Project Docs

- Interactive mode spec: `Docs/InteractiveMode.md`
- Schema docs: `Docs/Schema/README.md`
- Feature plans/specs: `Docs/Features/`
- Task plans: `Docs/Tasks/`

## Release (Maintainers)

- Release process: `RELEASE.md`
- Homebrew formula source: `HomebrewFormula/`
- Tap repo: `alvarhansen/homebrew-xcodequery`
