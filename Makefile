.PHONY: build test release xcq-bin wasm-image wasm-build wasm-web

HOST_ROOT ?= $(PWD)/..
CONTAINER_ROOT ?= /work
WORKDIR ?= $(CONTAINER_ROOT)/XcodeQuery
WASM_IMAGE ?= xcodequery-wasm:6.2.3
WASM_PLATFORM ?= linux/amd64
WASM_SDK_ID ?= swift-6.2.3-RELEASE_wasm
WASM_BUILD_ARGS ?=
WASM_BUILD_PATH ?= $(WORKDIR)/.build-wasm
WASM_WEB_PRODUCT ?= xcodequery-wasm
WASM_WEB_OUT ?= $(WORKDIR)/web/$(WASM_WEB_PRODUCT).wasm

WASM_PLATFORM_FLAG := $(if $(WASM_PLATFORM),--platform=$(WASM_PLATFORM),)
WASM_CMD = docker run --rm $(WASM_PLATFORM_FLAG) -v "$(HOST_ROOT)":$(CONTAINER_ROOT) -w $(WORKDIR) $(WASM_IMAGE)
WASM_BUILD_CMD = docker build $(WASM_PLATFORM_FLAG) -t $(WASM_IMAGE) -f Dockerfile.wasm .

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

wasm-image:
	$(WASM_BUILD_CMD)

wasm-build:
	$(WASM_CMD) swift build --swift-sdk $(WASM_SDK_ID) --build-path $(WASM_BUILD_PATH) $(WASM_BUILD_ARGS)

wasm-web:
	$(WASM_CMD) swift build --swift-sdk $(WASM_SDK_ID) --build-path $(WASM_BUILD_PATH) --product $(WASM_WEB_PRODUCT) $(WASM_BUILD_ARGS)
	$(WASM_CMD) mkdir -p $(WORKDIR)/web
	$(WASM_CMD) cp $(WASM_BUILD_PATH)/wasm32-unknown-wasip1/debug/$(WASM_WEB_PRODUCT).wasm $(WASM_WEB_OUT)
