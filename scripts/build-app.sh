#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/build/ProtonKit.app"

# --- Bootstrap .app skeleton if missing (fresh clone) ---
if [ ! -d "$APP_DIR/Contents/MacOS" ]; then
    echo "Creating .app bundle skeleton..."
    mkdir -p "$APP_DIR/Contents/MacOS"
    mkdir -p "$APP_DIR/Contents/Resources"
    mkdir -p "$APP_DIR/Contents/Frameworks"

    cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ProtonKit</string>
    <key>CFBundleIdentifier</key>
    <string>com.protonkit.app</string>
    <key>CFBundleName</key>
    <string>ProtonKit</string>
    <key>CFBundleDisplayName</key>
    <string>ProtonKit</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <false/>
    </dict>
</dict>
</plist>
PLIST
fi

# --- Generate app icon if missing ---
if [ ! -f "$APP_DIR/Contents/Resources/AppIcon.icns" ]; then
    echo "Generating app icon..."
    swift "$PROJECT_DIR/scripts/generate-icon.swift"

    ICONSET_DIR="/tmp/ProtonKit_AppIcon.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    for sz in 16 32 128 256 512; do
        sips -z $sz $sz /tmp/protonkit_icon_1024.png --out "$ICONSET_DIR/icon_${sz}x${sz}.png" > /dev/null
    done
    sips -z 32 32   /tmp/protonkit_icon_1024.png --out "$ICONSET_DIR/icon_16x16@2x.png"   > /dev/null
    sips -z 64 64   /tmp/protonkit_icon_1024.png --out "$ICONSET_DIR/icon_32x32@2x.png"   > /dev/null
    sips -z 256 256 /tmp/protonkit_icon_1024.png --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
    sips -z 512 512 /tmp/protonkit_icon_1024.png --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
    cp /tmp/protonkit_icon_1024.png "$ICONSET_DIR/icon_512x512@2x.png"

    iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
fi

# --- Build ---
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
