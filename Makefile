.PHONY: build test release xq-bin

# Build the debug binary
build:
	swift build -c debug

# Run the test suite (debug)
test:
	swift test -c debug

# Build the release binary
release:
	swift build -c release

# Print the path to the built xq binary
xq-bin:
	@swift build -c debug --show-bin-path | { read bin; echo "$$bin/xq"; }

# Install via local Homebrew formula (builds release and links to Homebrew prefix)
brew-local:
	brew install --build-from-source --formula ./HomebrewFormula/xq.rb
