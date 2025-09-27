# Info.plist Introspection — Plan & Spec

Provide per-target Info.plist inspection with configuration awareness for common keys and raw key/value access.

## Objectives

- Resolve `INFOPLIST_FILE` per configuration and expose:
  - Common keys: bundleIdentifier, versionShort, version, displayName, executable, bundleName, packageType.
  - File path to the plist.
  - Optional raw `keys` view with filter by key name.
- Minimal macro expansion for paths (SRCROOT/PROJECT_DIR) and string values for common keys (best-effort).

Non-goals (initial):
- Full build setting interpolation or `INFOPLIST_OTHER_PREPROCESSOR_FLAGS` handling.

## UX Overview

- `target(name: "App") { infoPlist(configuration: "Release") { path bundleIdentifier versionShort version } }`
- Keys filter: `target(name: "App") { infoPlist { keys(filter: { key: { prefix: "CFBundle" } }) { key value } } }`

## CLI Additions

- None required; query-surface only.

## Schema & Types

- Target addition
  - `infoPlist(configuration: String = null, filter: InfoPlistFilter = null): InfoPlist!`

Types
- `type InfoPlist { path: String!, bundleIdentifier: String, versionShort: String, version: String, displayName: String, executable: String, bundleName: String, packageType: String, keys(filter: InfoPlistKeyFilter): [InfoPlistEntry!]! }`
- `type InfoPlistEntry { key: String!, value: String! }`

Inputs
- `input InfoPlistFilter { }` (reserved for future; not used initially)
- `input InfoPlistKeyFilter { key: StringMatch }`

## Architecture & Components

- Determine plist path:
  - Read build settings for the target per configuration (or default) to find `INFOPLIST_FILE`.
  - Expand `$(SRCROOT)`/`$(PROJECT_DIR)`; leave other macros as-is.
- Load plist as dictionary and map common keys.
- `keys` view maps to an array of key/value strings with filter.

## Testing Strategy

- Fixture targets with distinct Debug/Release plist values for identifiers/versions.
- Assertions on:
  - Path resolution for relative and absolute paths.
  - Correct values for common keys and filtered `keys`.

## Implementation Tasks

1) Schema types and target field
2) Resolver to resolve path, load plist (XML/binary), extract keys
3) Tests and examples; docs and release notes

## Milestones & Estimates

- M12-01 (Schema): 0.25 day
- M12-02 (Resolvers): 0.75 day
- M12-03 (Tests/docs): 0.5 day

## Risks & Mitigations

- Complex build setting interpolation: keep minimal and document limitations.
- Missing plist: return empty struct with path set (or throw?) — choose to throw a GraphQL error if file missing.

