# Xcode Query

## Examples

`xq '.targets'`

`xq '.targets[] | filter(.type == .unitTest)'`

`xq '.targets[] | filter(.name.hasSuffix("Tests"))'`
`xq '.targets[] | filter(.name | hasSuffix("Tests"))'`

