.PHONY: build test release xcq-bin

# Build the debug binary
build:
	swift build -c debug

# Run the test suite (debug)
test:
	swift test -c debug

# Build the release binary
release:
	swift build -c release

# Print the path to the built xcq binary
xcq-bin:
	@swift build -c debug --show-bin-path | { read bin; echo "$$bin/xcq"; }

# Install via local Homebrew formula (builds release and links to Homebrew prefix)
brew-local:
	brew install --build-from-source --formula ./HomebrewFormula/xcq.rb
