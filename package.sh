#!/bin/bash
set -e

cd "$(dirname "$0")"

APP_NAME="Halo"
BUNDLE_ID="com.gongping.halo"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

# 是否安装到 /Applications（默认否；传 install 参数则安装）
INSTALL_APP=0
if [[ "$1" == "install" ]]; then
    INSTALL_APP=1
fi

echo "==> Building release..."
swift build -c release

# 动态获取真实的构建产物目录（兼容不同 Swift/Xcode toolchain）
BIN_PATH="$(swift build -c release --show-bin-path)"
BUILD_DIR="$(dirname "$BIN_PATH")"

echo "==> Packaging $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy resources (bundle)
if [ -d "$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy icon
if [ -f "$DIST_DIR/$APP_NAME.icns" ]; then
    cp "$DIST_DIR/$APP_NAME.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Write Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleDisplayName</key><string>Halo</string>
    <key>CFBundleExecutable</key><string>Halo</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>Halo.icns</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Halo</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 代码签名（ad-hoc，本地运行必需，否则 macOS 可能拒绝启动未签名 app）
echo "==> Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || echo "    (签名跳过或失败，本地运行通常仍可)"

# Create zip
echo "==> Creating zip..."
cd "$DIST_DIR"
rm -f "$APP_NAME-macOS.zip"
zip -r "$APP_NAME-macOS.zip" "$APP_NAME.app" >/dev/null
cd ..

echo "==> Done! $APP_BUNDLE"

# 安装到 /Applications
if [[ "$INSTALL_APP" == "1" ]]; then
    TARGET="/Applications/$APP_NAME.app"
    echo "==> Installing to $TARGET ..."

    # 关闭正在运行的旧实例
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "    closing running $APP_NAME ..."
        osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
        sleep 1
    fi

    # 备份旧版本到 dist（用 trash 而不是直接删除，更安全）
    if [ -d "$TARGET" ]; then
        BACKUP="$DIST_DIR/${APP_NAME}.app.old.$(date +%Y%m%d%H%M%S)"
        echo "    backing up old version to $BACKUP"
        mv "$TARGET" "$BACKUP"
    fi

    cp -R "$APP_BUNDLE" "$TARGET"

    # 移除隔离属性，避免 Gatekeeper 拦截
    xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

    echo "==> Installed. Launching..."
    open "$TARGET"
    echo "==> Done! Halo 已更新并启动。"
fi
