# MacFan

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Русский](README.ru.md)

A compact, native fan controller for Apple Silicon Macs running macOS 13 or
later.

## Features

- Independent left and right fan policies
- Automatic, fixed-speed, and custom temperature-curve modes
- Login launch switch in the menu bar panel
- Native SwiftUI interface with no web runtime
- Low-frequency adaptive sampling and size-optimized release builds
- Root helper with signed XPC client verification
- Five-second dead-man switch and emergency maximum-speed protection

MacBook Air and other fanless Macs have no controllable fan. Sensor availability
and SMC behavior vary by hardware generation.

## Install from DMG

1. Download `MacFan-<version>-arm64.dmg` from Releases.
2. Open the DMG and drag MacFan into Applications.
3. GitHub builds are ad-hoc signed and not Apple-notarized. Remove the quarantine
   attribute before the first launch:

```shell
xattr -cr /Applications/MacFan.app
open /Applications/MacFan.app
```

If macOS reports insufficient permission, run only the quarantine removal with
administrator privileges:

```shell
sudo xattr -rd com.apple.quarantine /Applications/MacFan.app
```

Do not disable Gatekeeper globally. Approve MacFan under System Settings →
General → Login Items when macOS asks to enable its background helper.

## Build

Requirements:

- Apple Silicon Mac
- macOS 13 or later
- A current full Xcode installation
- XcodeGen only when regenerating the project

Open `MacFan.xcodeproj`, select the MacFan scheme, choose a development team,
and run. To regenerate the project:

```shell
xcodegen generate
```

Tagged pushes matching `v*` run the GitHub Actions release workflow, build an
arm64 application, apply an ad-hoc signature, create a compressed DMG and SHA-256
file, and attach both to the GitHub release.

## Safety

Targets are clamped to hardware-reported RPM limits. Invalid sensors, helper
failure, heartbeat loss, and application exit restore system fan control.
At the emergency threshold, available fans immediately switch to maximum speed.
