#!/bin/bash
# Build SyncLight Pro as a native arm64 .app bundle.
set -e

APP_NAME="SyncLightPro"
DISPLAY_NAME="SyncLight Pro"
BUNDLE_DIR="build/${DISPLAY_NAME}.app"
CONFIG="${1:-release}"   # release | debug

echo "==> Building ($CONFIG) for arm64..."
swift build -c "$CONFIG" --arch arm64

BIN_PATH="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/${APP_NAME}"

echo "==> Assembling app bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$BIN_PATH" "$BUNDLE_DIR/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE_DIR/Contents/PkgInfo"

# Menu-bar icon (optional custom PNG bundled into Resources).
if [ -f "Resources/menu bar.png" ]; then
    cp "Resources/menu bar.png" "$BUNDLE_DIR/Contents/Resources/menu bar.png"
fi

# App icon: build .icns from a PNG (preferred) or the SVG when present.
if [ -f "Resources/AppIcon.png" ] || [ -f "Resources/SyncLight Pro.png" ] || [ -f "Resources/SyncLight Pro.svg" ]; then
    echo "==> Building app icon..."
    bash make_icon.sh
    if [ -f "build/AppIcon.icns" ]; then
        cp "build/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
        /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$BUNDLE_DIR/Contents/Info.plist" 2>/dev/null \
          || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$BUNDLE_DIR/Contents/Info.plist"
    fi
fi

echo "==> Ad-hoc codesigning..."
codesign --force --deep --sign - "$BUNDLE_DIR"

echo "==> Done: $BUNDLE_DIR"
echo "    Run with: open \"$BUNDLE_DIR\""
