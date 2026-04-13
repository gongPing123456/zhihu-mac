# Halo

Halo 是一个面向 macOS 的知乎阅读客户端，主打轻量、快速浏览和键盘翻页。

## 下载

请从 Releases 页面下载最新构建：

- [Halo Releases](https://github.com/gongPing123456/zhihu-mac/releases)

## 功能

- 页面：`首页`、`热榜`
- 阅读区 + 评论区双栏浏览
- 评论查看（根评论 + 子评论展开）
- 键盘翻页：
  - `←` / `A`：上一条
  - `→` / `D`：下一条
- 登录：
  - 内置 WebView 扫码登录
  - 登录成功后自动生效（无需重启应用）

## 系统要求

- macOS 14 或更高版本

## 从源码运行

```bash
git clone git@github.com:gongPing123456/zhihu-mac.git
cd zhihu-mac
swift run Halo
```

也可以直接使用 Xcode 打开 `Package.swift` 运行。

## 打包

### 为什么 `swift build` 后是 `exec`

`swift build` 针对 Swift Package 的 `executableTarget` 默认产出的是可执行文件，因此你直接在 `.build/.../release/` 里看到的会是 `Halo` 二进制，而不是 `.app` 包。这是 SwiftPM 的正常行为，不是构建失败。

### 生成可双击启动的 `.app`

```bash
BIN_PATH="$(swift build --configuration release --show-bin-path)"
ICONSET="dist/Halo.iconset"; APP_PATH="dist/Halo.app"; rm -rf "$ICONSET" "$APP_PATH"; mkdir -p "$ICONSET" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"; for size in 16 32 128 256 512; do sips -z $size $size Sources/Halo/Resources/HaloIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null; sips -z $((size * 2)) $((size * 2)) Sources/Halo/Resources/HaloIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null; done; iconutil -c icns "$ICONSET" -o dist/Halo.icns; cp "$BIN_PATH/Halo" "$APP_PATH/Contents/MacOS/Halo"; cp -R "$BIN_PATH/Halo_Halo.bundle" "$APP_PATH/Contents/Resources/"; cp dist/Halo.icns "$APP_PATH/Contents/Resources/Halo.icns"; chmod +x "$APP_PATH/Contents/MacOS/Halo"; cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleDisplayName</key><string>Halo</string>
    <key>CFBundleExecutable</key><string>Halo</string>
    <key>CFBundleIdentifier</key><string>com.gongping.halo</string>
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
open "$APP_PATH"
```

执行完成后，`dist/Halo.app` 就是可以双击启动的完整 macOS 应用。

### 导出 ZIP

```bash
ditto -c -k --sequesterRsrc --keepParent dist/Halo.app dist/Halo-macOS.zip
```

### 导出 DMG

```bash
hdiutil create -volname "Halo" -srcfolder dist/Halo.app -ov -format UDZO dist/Halo.dmg
```

最终产物说明：

- `dist/Halo.app`：本地双击运行的应用包
- `dist/Halo-macOS.zip`：适合放到 GitHub Releases 的压缩包
- `dist/Halo.dmg`：标准 macOS 安装镜像

## 开发说明

- 项目基于 SwiftUI + Swift Package Manager。
- 若评论接口出现 `403`，通常是登录态失效或接口风控，建议重新扫码登录后重试。
