# M12-01 — Phase 2: Info.plist Resolvers

Goal: Implement resolver for `Target.infoPlist` with configuration handling and minimal expansion.

## Tasks

1) Resolve configuration
   - If `configuration` arg is provided, use it; otherwise prefer the first available configuration (e.g., Debug) deterministically.

2) Resolve `INFOPLIST_FILE`
   - From target build settings for that configuration; if missing, check project-level settings.
   - Expand `$(SRCROOT)` and `$(PROJECT_DIR)` only.

3) Load and map plist
   - Support XML and binary plist.
   - Extract common keys: CFBundleIdentifier/CFBundleShortVersionString/CFBundleVersion/CFBundleDisplayName/CFBundleExecutable/CFBundleName/CFBundlePackageType.
   - Build `keys` array as stringified key-value pairs.

4) Filters and ordering
   - `keys(filter: { key: ... })` uses `StringMatch` on key names.
   - Sort keys alphabetically.

## Acceptance Criteria

- Correct plist resolution and value mapping for a fixture with distinct Debug/Release values.

