.PHONY: simulator build clean help list-simulators

# Project settings
SCHEME = BetterAuthBasicExample
PROJECT = BetterAuthBasicExample.xcodeproj
SIMULATOR_NAME ?= iPhone 17 Pro
BUILD_DIR = .build
DERIVED_DATA = $(BUILD_DIR)/DerivedData

# Build for generic iOS simulator (avoids simulator plugin issues)
build:
	@echo "Building $(SCHEME)..."
	@SIMULATOR_ID=$$(xcrun simctl list devices | grep "$(SIMULATOR_NAME)" | grep -v "unavailable" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/'); \
	if [ -z "$$SIMULATOR_ID" ]; then \
		echo "Error: Simulator '$(SIMULATOR_NAME)' not found"; \
		exit 1; \
	fi; \
	xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination "id=$$SIMULATOR_ID" \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		build

# Launch in simulator
simulator: build
	@echo "Launching app in simulator..."
	@APP_PATH=$$(find $(DERIVED_DATA) -name "$(SCHEME).app" -type d | head -1); \
	if [ -z "$$APP_PATH" ]; then \
		echo "Error: Could not find built app"; \
		exit 1; \
	fi; \
	echo "Found app at: $$APP_PATH"; \
	SIMULATOR_ID=$$(xcrun simctl list devices | grep "$(SIMULATOR_NAME)" | grep -v "unavailable" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/'); \
	if [ -z "$$SIMULATOR_ID" ]; then \
		echo "Error: Simulator '$(SIMULATOR_NAME)' not found"; \
		echo "Available simulators:"; \
		xcrun simctl list devices | grep -v "unavailable" | grep "iPhone"; \
		exit 1; \
	fi; \
	echo "Using simulator: $$SIMULATOR_ID ($(SIMULATOR_NAME))"; \
	xcrun simctl boot $$SIMULATOR_ID 2>/dev/null || true; \
	open -a Simulator; \
	sleep 2; \
	echo "Installing app..."; \
	xcrun simctl install $$SIMULATOR_ID "$$APP_PATH"; \
	BUNDLE_ID=$$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$$APP_PATH/Info.plist"); \
	echo "Launching app with bundle ID: $$BUNDLE_ID"; \
	xcrun simctl launch --console $$SIMULATOR_ID $$BUNDLE_ID

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@echo "Build artifacts cleaned"

# List available simulators
list-simulators:
	@echo "Available iOS simulators:"
	@xcrun simctl list devices | grep -v "unavailable" | grep "iPhone"

# Help
help:
	@echo "BetterAuth iOS Example App - Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make simulator        - Build and run app in simulator"
	@echo "  make build            - Build app for simulator"
	@echo "  make clean            - Clean build artifacts"
	@echo "  make list-simulators  - List available iOS simulators"
	@echo "  make help             - Show this help message"
	@echo ""
	@echo "Environment variables:"
	@echo "  SIMULATOR_NAME        - Target simulator (default: $(SIMULATOR_NAME))"
	@echo ""
	@echo "Example:"
	@echo "  make simulator SIMULATOR_NAME='iPhone 15'"
