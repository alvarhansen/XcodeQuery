# XcodeQuery — Local Release Process

This project does not use CI automation for releases. Maintainers cut releases locally.

Follow these steps to publish a new version and update the Homebrew formula.

## 0) Prerequisites
- macOS 15 with Xcode toolchain installed (for Swift 6).
- Homebrew installed (for local formula testing).
- Write access to:
  - GitHub repo: `alvarhansen/XcodeQuery`
  - Homebrew tap: `alvarhansen/homebrew-xcodequery`
- CLI tools: `git`, `zip`, `shasum`, `curl`.

## 1) Prepare the release
- Ensure the working tree is clean and on `main`.
- Update docs (if needed): `Readme.md`, feature docs, etc.
- Build and test locally:
  - `make build`
  - `make test`

## 2) Choose a version and tag
- Decide a semantic version like `vX.Y.Z`.
- Create and push the tag:
  - `git tag vX.Y.Z`
  - `git push origin vX.Y.Z`

## 3) Build a release binary and zip
- Build the release binary:
  - `make release`
- Create an archive (zip includes the binary and README):
  - `mkdir -p dist`
  - `cp .build/release/xcq dist/xcq`
  - `cp Readme.md dist/`
  - `cd dist && zip -r xcq-vX.Y.Z-macos.zip xcq Readme.md && rm -f xcq Readme.md && cd -`
- Compute checksum:
  - `shasum -a 256 dist/xcq-vX.Y.Z-macos.zip`

## 4) Create the GitHub Release (gh CLI)
Release creation is done with the GitHub CLI. Ensure you are logged in:

- Check auth: `gh auth status` (login if needed: `gh auth login`)

Create the release with the tag and upload the built zip:

- `gh release create vX.Y.Z dist/xcq-vX.Y.Z-macos.zip -t "vX.Y.Z" -n "Release vX.Y.Z"`

Options:
- Auto-generate notes: add `--generate-notes` (and optionally append your own with `-n`).
- Use a notes file: `-F path/to/notes.md`.

## 5) Update Homebrew formula (prebuilt by default)
Stable installs use the prebuilt release zip asset. Update the URL and SHA to the zip.

- Compute zip checksum (from step 3):
  - `shasum -a 256 dist/xcq-vX.Y.Z-macos.zip` → copy the SHA256
- Edit `HomebrewFormula/xcq.rb` and set stable to the release asset:
  - `url "https://github.com/alvarhansen/XcodeQuery/releases/download/vX.Y.Z/xcq-vX.Y.Z-macos.zip"`
  - `sha256 "<THE_SHA256_OF_ZIP>"`
- Ensure the formula's `install` copies the binary when not building `--HEAD`.
- Commit and push:
  - `git add HomebrewFormula/xcq.rb && git commit -m "Homebrew: xcq vX.Y.Z (prebuilt)"`
  - `git push origin main`

## 6) Publish the updated formula to the tap
- Clone/update the tap repo: `git clone git@github.com:alvarhansen/homebrew-xcodequery.git`
- Copy updated formula into the tap repo (replace existing `xcq.rb`).
- Commit and push in the tap repo:
  - `git add Formula/xcq.rb && git commit -m "xcq vX.Y.Z (prebuilt)"`
  - `git push origin main`

## 7) Verify Homebrew install
- From a clean machine/shell:
  - `brew tap alvarhansen/xcodequery`
  - `brew install xcq`
  - Run `xcq --help`

## 8) Post-release
- Update `Readme.md` examples or feature docs if needed.
- Announce the release.

Notes
- If you prefer distributing the prebuilt zip, you may author a separate cask; the current formula builds from source and points at the GitHub tag tarball.
- If you change packaging or binary name, update this document and the formula accordingly.
