# AIMonitor build + bundle assembly. No Xcode required.
APP_NAME    := AIMonitor
BUNDLE_ID   := dev.mgks.aimonitor
CONFIG      := release
BIN_PATH    := $(shell swift build -c $(CONFIG) --show-bin-path)
APP_DIR     := $(APP_NAME).app
CONTENTS    := $(APP_DIR)/Contents
MACOS_DIR   := $(CONTENTS)/MacOS
RESOURCES_DIR := $(CONTENTS)/Resources
ICONSET_DIR := AppIcon.iconset
ICON_ICNS   := AppIcon.icns

.PHONY: all build run bundle icon clean help deploy test

help:
	@echo "make build   - compile (release)"
	@echo "make run     - run from source (shows dock icon, good for dev)"
	@echo "make icon    - render AppIcon.icns from the Swift icon script"
	@echo "make bundle  - assemble AIMonitor.app (menu-bar only, with icon)"
	@echo "make deploy  - copy to /Applications and launch"
	@echo "make test    - run unit tests (requires Xcode for XCTest)"
	@echo "make clean   - remove build artifacts and .app"

build:
	swift build -c $(CONFIG)

test:
	@echo ">> running tests (requires Xcode for XCTest)"
	swift test 2>&1 || echo "Note: XCTest requires Xcode.app. Install Xcode to run unit tests."

run:
	swift run

# Render the .icns from the SVG icon source via NSImage rasterisation.
icon:
	@echo ">> rendering icon set"
	@rm -rf $(ICONSET_DIR) $(ICON_ICNS)
	@swift scripts/render-icon.swift $(ICONSET_DIR)
	@iconutil -c icns -o $(ICON_ICNS) $(ICONSET_DIR)
	@rm -rf $(ICONSET_DIR)
	@echo ">> wrote $(ICON_ICNS)"

# Assemble a proper .app bundle so LSUIElement takes effect.
bundle: build icon
	@echo ">> assembling $(APP_DIR)"
	@rm -rf $(APP_DIR)
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	@cp "$(BIN_PATH)/$(APP_NAME)" "$(MACOS_DIR)/$(APP_NAME)"
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@if [ -f $(ICON_ICNS) ]; then cp $(ICON_ICNS) "$(RESOURCES_DIR)/AppIcon.icns"; else echo "  (no icon)"; fi
	@echo ">> built $(APP_DIR)"

# Deploy to /Applications for live testing.
deploy: bundle
	@echo ">> deploying to /Applications"
	@pkill -f "$(APP_NAME).app" 2>/dev/null || true
	@rm -rf /Applications/$(APP_DIR)
	@cp -R $(APP_DIR) /Applications/$(APP_DIR)
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/$(APP_DIR) 2>/dev/null || true
	@open -a /Applications/$(APP_DIR)
	@echo ">> launched from /Applications"

clean:
	swift package clean
	rm -rf $(APP_DIR) $(ICONSET_DIR) $(ICON_ICNS)
