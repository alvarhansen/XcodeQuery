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

