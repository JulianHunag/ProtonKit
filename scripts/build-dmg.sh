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

echo ""
echo "Done! DMG created at:"
echo "  $DMG_PATH"
