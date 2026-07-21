# AIStat build + bundle assembly. No Xcode required.
APP_NAME    := AIStat
BUNDLE_ID   := dev.mgks.aistat
CONFIG      := release
BIN_PATH    := $(shell swift build -c $(CONFIG) --show-bin-path)
APP_DIR     := $(APP_NAME).app
CONTENTS    := $(APP_DIR)/Contents
MACOS_DIR   := $(CONTENTS)/MacOS
RESOURCES_DIR := $(CONTENTS)/Resources
ICONSET_DIR := AppIcon.iconset
ICON_ICNS   := AppIcon.icns

.PHONY: all build run bundle icon clean help

help:
	@echo "make build   - compile (release)"
	@echo "make run     - run from source (shows dock icon, good for dev)"
	@echo "make icon    - render AppIcon.icns from the Swift icon script"
	@echo "make bundle  - assemble AIStat.app (menu-bar only, with icon)"
	@echo "make clean   - remove build artifacts and .app"

build:
	swift build -c $(CONFIG)

run:
	swift run

# Render the .icns from the CoreGraphics icon script. No Xcode or rsvg needed.
icon:
	@echo ">> rendering icon set"
	@rm -rf $(ICONSET_DIR) $(ICON_ICNS)
	@swift scripts/render-icon.swift $(ICONSET_DIR)
	@iconutil -c icns -o $(ICON_ICNS) $(ICONSET_DIR)
	@rm -rf $(ICONSET_DIR)
	@echo ">> wrote $(ICON_ICNS)"

# Assemble a proper .app bundle so LSUIElement takes effect.
# swift run alone shows a dock icon; the bundle does not.
bundle: build icon
	@echo ">> assembling $(APP_DIR)"
	@rm -rf $(APP_DIR)
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	@cp "$(BIN_PATH)/$(APP_NAME)" "$(MACOS_DIR)/$(APP_NAME)"
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@if [ -f $(ICON_ICNS) ]; then cp $(ICON_ICNS) "$(RESOURCES_DIR)/AppIcon.icns"; else echo "  (no icon)"; fi
	@echo ">> built $(APP_DIR)"
	@echo "   open with:  open $(APP_DIR)"

clean:
	swift package clean
	rm -rf $(APP_DIR) $(ICONSET_DIR) $(ICON_ICNS)
