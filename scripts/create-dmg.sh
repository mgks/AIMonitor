#!/bin/bash
# Creates a DMG with a proper drag-to-Applications installer window.
# No external tools required - uses only hdiutil + AppleScript.

set -e

APP_NAME="AIMonitor"
APP_DIR="AIMonitor.app"
DMG_NAME="AIMonitor-0.1.0.dmg"
STAGING="dmg-staging"
VOL_NAME="AIMonitor"

echo ">> building app bundle..."
make bundle > /dev/null 2>&1

echo ">> staging DMG contents..."
rm -rf "$STAGING" "$DMG_NAME"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo ">> creating DMG..."
# Create a read-write DMG first so we can set the window layout.
RW_DMG="temp-rw.dmg"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGING" -fs HFS+ \
    -format UDRW -size 10m "$RW_DMG" > /dev/null 2>&1

# Mount it.
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" 2>/dev/null \
    | grep -m1 '/Volumes/' | awk '{print $NF}')
echo ">> mounted at: $MOUNT_DIR"

# Set the window layout via AppleScript.
# Position: AIMonitor.app on left, Applications on right, icon view, 120x120 icons.
osascript <<APPLE_EOF
tell application "Finder"
    set volumePath to POSIX file "$MOUNT_DIR" as alias
    tell folder volumePath
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 520, 320}
        set view options of container window to icon view
        set arrangement of icon view options of container window to not arranged
        set icon size of icon view options of container window to 100
        set position of item "$APP_NAME.app" of container window to {130, 110}
        set position of item "Applications" of container window to {290, 110}
        close
        open
    end tell
end tell
APPLE_EOF

# Set custom volume icon (the app icon).
cp "$APP_DIR/Contents/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
SetFile -a C "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true

# Unmount.
hdiutil detach "$MOUNT_DIR" > /dev/null 2>&1

# Convert to read-only compressed DMG.
echo ">> compressing DMG..."
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME" > /dev/null 2>&1
rm -f "$RW_DMG"
rm -rf "$STAGING"

echo ">> built $DMG_NAME"
ls -lh "$DMG_NAME" | awk '{printf "   size: %s\n", $5}'
