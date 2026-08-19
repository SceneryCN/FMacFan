# MacFan

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Русский](README.ru.md)

适用于 macOS 13 及更高版本 Apple 芯片 Mac 的轻量原生风扇控制工具。

## 功能

- 左右风扇独立控制
- 系统自动、固定转速和自定义温度曲线
- 菜单栏面板内提供开机自启开关
- 纯 SwiftUI 原生界面，不包含 Web 运行时
- 自适应低频采样和体积优化构建
- root Helper 与签名 XPC 客户端校验
- 5 秒失联保护和高温立即满速保护

MacBook Air 等无风扇机型没有可控制的风扇。不同硬件世代提供的传感器
和 SMC 行为可能不同。

## 通过 DMG 安装

1. 从 Releases 下载 `MacFan-<版本>-arm64.dmg`。
2. 打开 DMG，将 MacFan 拖入“应用程序”。
3. GitHub 构建仅使用临时签名，未经过 Apple 公证。首次启动前运行：

```shell
xattr -cr /Applications/MacFan.app
open /Applications/MacFan.app
```

如果提示权限不足，仅对隔离属性清理命令使用管理员权限：

```shell
sudo xattr -rd com.apple.quarantine /Applications/MacFan.app
```

不要全局关闭 Gatekeeper。系统提示时，请在“系统设置 → 通用 → 登录项”
中允许 MacFan 后台 Helper。

## 构建

需要 Apple 芯片 Mac、macOS 13+ 和完整的最新版 Xcode。只有重新生成工程
时才需要 XcodeGen。

打开 `MacFan.xcodeproj`，选择 MacFan Scheme，设置开发团队后运行。
重新生成工程：

```shell
xcodegen generate
```

推送符合 `v*` 的 Tag 后，GitHub Actions 会构建 arm64 应用、应用临时
签名、创建压缩 DMG 与 SHA-256 文件，并将它们上传至 GitHub Release。

## 安全保护

目标转速始终限制在硬件报告的 RPM 范围内。传感器失效、Helper 异常、
心跳中断或应用退出时都会恢复系统控制。达到紧急温度时，风扇会立即满速。
