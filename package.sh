#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "==> Building release..."
swift build -c release

APP_NAME="Halo"
BUILD_DIR=".build/arm64-apple-macosx/release"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

echo "==> Packaging $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy resources (bundle)
if [ -d "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy icon
if [ -f "$DIST_DIR/$APP_NAME.icns" ]; then
    cp "$DIST_DIR/$APP_NAME.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Write Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Halo</string>
    <key>CFBundleIdentifier</key>
    <string>com.halo.app</string>
    <key>CFBundleName</key>
    <string>Halo</string>
    <key>CFBundleDisplayName</key>
    <string>Halo</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>Halo.icns</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Create zip
echo "==> Creating zip..."
cd "$DIST_DIR"
rm -f "$APP_NAME-macOS.zip"
zip -r "$APP_NAME-macOS.zip" "$APP_NAME.app"
cd ..

echo "==> Done! $APP_BUNDLE"
