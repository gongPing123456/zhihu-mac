# Halo

`Halo` 是一个面向 macOS 的知乎阅读客户端（SwiftUI + SPM），主打轻量、快速浏览和键盘翻页。

## 当前功能

- 顶部原生 Toolbar 布局（与 macOS 标题栏融合）
- 页面：`首页`、`热榜`
- 阅读区 + 评论区双栏浏览
- 评论查看（根评论 + 子评论展开）
- 键盘翻页：
  - `←` / `A` 上一条
  - `→` / `D` 下一条
- 登录：
  - 内置 WebView 扫码登录
  - 扫码成功后自动验证并生效（无需重启应用）
- 自定义应用图标（Halo）

## 环境要求

- macOS 14+
- Xcode 16+（或支持 Swift 6.1 的工具链）

## 本地运行

```bash
cd /Users/gongping/Documents/随便/ZhihuMoyuMac
swift run Halo
```

也可以直接用 Xcode 打开 `Package.swift` 运行。

## 打包（本地）

```bash
cd /Users/gongping/Documents/随便/ZhihuMoyuMac
swift build -c release
```

当前打包产物默认放在 `dist/`：

- `dist/Halo.app`
- `dist/Halo-macOS.zip`

## 说明

- 若评论接口出现 `403`，通常是登录态失效或接口风控，建议重新扫码登录后再试。
- 本项目是 SPM 工程（非 Xcode 工程模板），打包流程为自定义脚本式组装。
