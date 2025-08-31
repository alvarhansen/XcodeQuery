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
