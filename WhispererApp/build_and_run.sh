#!/bin/bash
set -e

cd "$(dirname "$0")"

# Generate app icon if it doesn't exist
if [ ! -f "AppIcon.icns" ] && [ ! -f "AppIcon.png" ]; then
    echo "=== Generating app icon ==="
    python3 generate_icon.py 2>/dev/null || echo "Icon generation skipped (Pillow or iconutil not available)"
fi

# Build
echo "=== Building WhispererApp ==="
swift build 2>&1

# Get the path to the built executable (handles arm64/x86_64 automatically)
BIN_PATH=$(swift build --show-bin-path)
EXEC="$BIN_PATH/WhispererApp"

if [ ! -f "$EXEC" ]; then
    echo "ERROR: Built executable not found at $EXEC"
    exit 1
fi

echo "=== Creating .app bundle ==="
APP="WhispererApp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Copy executable
cp "$EXEC" "$APP/Contents/MacOS/WhispererApp"

# Copy app icon if available
ICON_FILE=""
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    ICON_FILE="AppIcon"
elif [ -f "AppIcon.png" ]; then
    cp "AppIcon.png" "$APP/Contents/Resources/AppIcon.png"
    ICON_FILE="AppIcon"
fi

# Create Info.plist — LSUIElement makes it a menu-bar-only app (no Dock icon)
cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WhispererApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.whisperer.app</string>
    <key>CFBundleName</key>
    <string>Whisperer</string>
    <key>CFBundleDisplayName</key>
    <string>Whisperer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <!-- LSUIElement removed for diagnostic — app will show in Dock -->
    <!-- Once menu bar icon is confirmed working, re-enable with:
    <key>LSUIElement</key>
    <true/>
    -->
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Whisperer needs microphone access for voice transcription.</string>
PLIST

# Add icon reference if we have one
if [ -n "$ICON_FILE" ]; then
    cat >> "$APP/Contents/Info.plist" << PLIST
    <key>CFBundleIconFile</key>
    <string>$ICON_FILE</string>
PLIST
fi

cat >> "$APP/Contents/Info.plist" << 'PLIST'
</dict>
</plist>
PLIST

echo "=== .app bundle created at $APP ==="
echo "=== Launching (stdout/stderr shown here) ==="
echo ""

# Run the executable directly from the bundle so we see output in terminal.
# macOS recognizes the .app bundle structure and registers with WindowServer.
exec "$APP/Contents/MacOS/WhispererApp"
