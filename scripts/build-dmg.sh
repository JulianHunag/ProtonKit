#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/build/ProtonKit.app"
DMG_DIR="$PROJECT_DIR/build/dmg"
DMG_PATH="$PROJECT_DIR/build/ProtonKit.dmg"

echo "Building ProtonKit..."
cd "$PROJECT_DIR"
swift build -c release

echo "Copying release binary to .app bundle..."
cp .build/arm64-apple-macosx/release/ProtonKit "$APP_DIR/Contents/MacOS/ProtonKit"

echo "Embedding frameworks..."
rm -rf "$APP_DIR/Contents/Frameworks/ObjectivePGP.framework"
mkdir -p "$APP_DIR/Contents/Frameworks"
cp -R .build/arm64-apple-macosx/release/ObjectivePGP.framework "$APP_DIR/Contents/Frameworks/"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/Contents/MacOS/ProtonKit" 2>/dev/null || true
codesign --force --sign - "$APP_DIR/Contents/Frameworks/ObjectivePGP.framework"
codesign --force --sign - "$APP_DIR"

echo "Creating DMG..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "ProtonKit" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_DIR"

echo "Setting DMG icon..."
ICON_SRC="$PROJECT_DIR/resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" /tmp/tmpicon.icns
    sips -i /tmp/tmpicon.icns > /dev/null 2>&1
    DeRez -only icns /tmp/tmpicon.icns > /tmp/tmpicns.rsrc 2>&1
    Rez -append /tmp/tmpicns.rsrc -o "$DMG_PATH" 2>&1
    SetFile -a C "$DMG_PATH" 2>&1
    rm -f /tmp/tmpicon.icns /tmp/tmpicns.rsrc
fi

echo ""
echo "Done! DMG created at:"
echo "  $DMG_PATH"
