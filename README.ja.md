# MacFan

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Русский](README.ru.md)

macOS 13 以降の Apple シリコン Mac 向けに設計された、軽量なネイティブ
ファンコントローラーです。

## 機能

- 左右ファンの独立制御
- 自動、固定回転数、カスタム温度カーブ
- メニューバーパネルのログイン時起動スイッチ
- Web ランタイムを使用しないネイティブ SwiftUI
- 低頻度の適応型サンプリングとサイズ最適化ビルド
- root Helper と署名済み XPC クライアント検証
- 5 秒のデッドマン保護と緊急時の最大回転

MacBook Air などのファンレスモデルには制御可能なファンがありません。
利用可能なセンサーと SMC の動作は機種によって異なります。

## DMG からインストール

1. Releases から `MacFan-<version>-arm64.dmg` をダウンロードします。
2. DMG を開き、MacFan を「アプリケーション」にドラッグします。
3. GitHub ビルドはアドホック署名で、Apple の公証を受けていません。
   初回起動前に次を実行してください。

```shell
xattr -cr /Applications/MacFan.app
open /Applications/MacFan.app
```

権限不足と表示される場合は、隔離属性の削除だけを管理者権限で実行します。

```shell
sudo xattr -rd com.apple.quarantine /Applications/MacFan.app
```

Gatekeeper を全体で無効にしないでください。macOS の指示に従い、
「システム設定 → 一般 → ログイン項目」で MacFan の Helper を許可します。

## ビルド

Apple シリコン Mac、macOS 13 以降、完全版の最新 Xcode が必要です。
XcodeGen はプロジェクトを再生成する場合のみ必要です。

`MacFan.xcodeproj` を開き、MacFan スキームと開発チームを選択して実行します。

```shell
xcodegen generate
```

`v*` タグを Push すると、GitHub Actions が arm64 アプリをビルドし、
アドホック署名、圧縮 DMG、SHA-256 ファイルの作成と Release への添付を行います。

## 安全性

回転数はハードウェアが報告する範囲に制限されます。センサー異常、Helper
障害、ハートビート切断、アプリ終了時にはシステム制御へ戻ります。緊急温度
ではファンが直ちに最大回転になります。
