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

## 开发说明

- 项目基于 SwiftUI + Swift Package Manager。
- 若评论接口出现 `403`，通常是登录态失效或接口风控，建议重新扫码登录后重试。
