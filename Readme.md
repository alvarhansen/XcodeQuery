# Xcode Query

## Examples

`xq '.targets'`

`xq '.targets[] | filter(.type == .unitTest)'`

`xq '.targets[] | filter(.name.hasSuffix("Tests"))'`
`xq '.targets[] | filter(.name | hasSuffix("Tests"))'`

Reverse dependencies and dependency queries

- Direct deps of a target: `xq '.dependencies("App")'`
- Transitive deps of a target: `xq '.dependencies("App", recursive: true)'`
- Reverse deps (who depends on): `xq '.dependents("Lib")'`
- Reverse deps alias: `xq '.reverseDependencies("Lib")'` or `xq '.rdeps("Lib")'`
- Pipeline: filter then deps: `xq '.targets[] | filter(.type == .unitTest) | dependencies(recursive: true)'`

Source files

- Source files of a target: `xq '.sources("App")'`
- Pipeline: list files for selected targets: `xq '.targets[] | filter(.type == .framework) | sources'`

Notes

- By default, `.sources(...)` returns the file reference path as stored in the project (e.g., relative path from the group). See below for path options.

Target membership

- Targets for a file: `xq '.targetMembership("Shared/Shared.swift")'`
- With path mode: `xq '.targetMembership("Shared/Shared.swift", pathMode: "normalized")'`
- Pipeline: `xq '.targets[] | sources(pathMode: "normalized") | targetMembership'` (returns each file with the targets it belongs to)

jq examples

- Files used by multiple targets (normalized paths):
  - `xq '.targets[] | sources(pathMode: "normalized") | targetMembership' --project MyApp.xcodeproj | jq -r '.[] | select(.targets | length > 1) | "\(.path) -> \(.targets|join(", "))"'`

- Files not in any target (absolute paths):
  - `find "$(pwd)" \( -name "*.swift" -o -name "*.m" -o -name "*.mm" -o -name "*.c" -o -name "*.cc" -o -name "*.cpp" \) -not -path "$(pwd)/.build/*" -not -path "$(pwd)/**/*.xcodeproj/*" -print0 | xargs -0 -n1 -I{} sh -c 'xq ".targetMembership(\"{}\", pathMode: \"absolute\")" --project MyApp.xcodeproj' | jq -s '. | map(select(.targets | length == 0))'`

Path options (proposal)

- Add an optional argument to `sources` (and `targetMembership`) to control path formatting. Examples:
  - Absolute paths: `xq '.sources("App", pathMode: "absolute")'`
  - Normalized to project root: `xq '.sources("App", pathMode: "normalized")'`
  - Pipeline variant: `xq '.targets[] | filter(.type == .framework) | sources(pathMode: "normalized") | targetMembership'`
- Alternatively, a global CLI flag could be supported:
  - `--path-mode fileRef|absolute|normalized` (default: `fileRef`)

Planned behavior if implemented

- fileRef: return the raw `PBXFileReference.path`/`name` as-is (current default).
- absolute: resolve each file’s path using its `sourceTree` and the project location to produce a full absolute path.
- normalized: return a path relative to the project root directory (e.g., stripping the absolute prefix to make paths stable across machines).
- Build script queries

- Per-target scripts: `xq '.buildScripts("App")'`
- Pipeline: `xq '.targets[] | filter(.type == .framework) | buildScripts'`
- Filter script stage or name in pipeline:
  - Pre-build scripts: `xq '.targets[] | buildScripts | filter(.stage == .pre)'`
  - Name prefix: `xq '.targets[] | buildScripts | filter(.name.hasPrefix("Pre"))'`
