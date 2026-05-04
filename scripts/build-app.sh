#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/build/ProtonKit.app"

echo "Building ProtonKit..."
cd "$PROJECT_DIR"
swift build -c debug

echo "Copying binary to .app bundle..."
cp .build/arm64-apple-macosx/debug/ProtonKit "$APP_DIR/Contents/MacOS/ProtonKit"

echo "Embedding frameworks..."
rm -rf "$APP_DIR/Contents/Frameworks/ObjectivePGP.framework"
mkdir -p "$APP_DIR/Contents/Frameworks"
cp -R .build/arm64-apple-macosx/debug/ObjectivePGP.framework "$APP_DIR/Contents/Frameworks/"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/Contents/MacOS/ProtonKit" 2>/dev/null || true
codesign --force --sign - "$APP_DIR/Contents/Frameworks/ObjectivePGP.framework"
codesign --force --sign - "$APP_DIR"

echo "Syncing to /Applications..."
rm -rf /Applications/ProtonKit.app
cp -R "$APP_DIR" /Applications/ProtonKit.app

echo "Done! Launch with:"
echo "  open /Applications/ProtonKit.app"
