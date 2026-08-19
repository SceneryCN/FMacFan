# MacFan

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Русский](README.ru.md)

macOS 13 이상을 실행하는 Apple Silicon Mac용 경량 네이티브 팬 컨트롤러입니다.

## 기능

- 왼쪽과 오른쪽 팬 독립 제어
- 자동, 고정 속도, 사용자 지정 온도 곡선 모드
- 메뉴 막대 패널의 로그인 시 실행 스위치
- 웹 런타임이 없는 네이티브 SwiftUI
- 저빈도 적응형 샘플링과 크기 최적화 빌드
- root Helper와 서명된 XPC 클라이언트 검증
- 5초 데드맨 보호와 비상 최대 속도 보호

MacBook Air와 같은 팬리스 Mac에는 제어할 팬이 없습니다. 사용 가능한 센서와
SMC 동작은 하드웨어 세대에 따라 달라질 수 있습니다.

## DMG에서 설치

1. Releases에서 `MacFan-<version>-arm64.dmg`를 다운로드합니다.
2. DMG를 열고 MacFan을 응용 프로그램 폴더로 드래그합니다.
3. GitHub 빌드는 임시 서명만 적용되며 Apple 공증을 받지 않았습니다.
   처음 실행하기 전에 다음 명령을 실행하세요.

```shell
xattr -cr /Applications/MacFan.app
open /Applications/MacFan.app
```

권한 부족 오류가 표시되면 격리 속성 제거 명령에만 관리자 권한을 사용하세요.

```shell
sudo xattr -rd com.apple.quarantine /Applications/MacFan.app
```

Gatekeeper를 전역으로 비활성화하지 마세요. macOS에서 요청하면 시스템 설정 →
일반 → 로그인 항목에서 MacFan Helper를 허용하세요.

## 빌드

Apple Silicon Mac, macOS 13 이상, 최신 전체 Xcode가 필요합니다. XcodeGen은
프로젝트를 다시 생성할 때만 필요합니다.

`MacFan.xcodeproj`를 열고 MacFan Scheme과 개발 팀을 선택한 다음 실행하세요.

```shell
xcodegen generate
```

`v*` 태그를 푸시하면 GitHub Actions가 arm64 앱을 빌드하고 임시 서명, 압축
DMG와 SHA-256 파일 생성, GitHub Release 첨부를 수행합니다.

## 안전

목표 속도는 하드웨어가 보고한 RPM 범위로 제한됩니다. 센서 오류, Helper 장애,
하트비트 손실 또는 앱 종료 시 시스템 팬 제어로 복구됩니다. 비상 온도에서는
팬이 즉시 최대 속도로 전환됩니다.
