# Mac Commander

macOS용 마크다운 파일 탐색 · 편집 앱. SwiftUI로 작성한 네이티브 앱입니다.

*A native macOS app for browsing and editing Markdown files — with math, diagrams, a built-in terminal, and multi-panel viewers. Open source under GPLv3.*

**➡️ [최신 버전 다운로드](https://github.com/codegeargit/mac-commander-releases/releases/latest)** · [소개 페이지](https://codegeargit.github.io/mac-commander-releases/)

## 주요 기능

- 폴더 트리와 문서 뷰어를 나란히 두는 2-pane 화면, 뷰어 패널 최대 3개 분할
- Total Commander식 듀얼 트리(⇧⌘D) — F5·F6으로 반대편 트리에 복사·이동, 하단 F키 바
- 마크다운 렌더링 — LaTeX 수식(KaTeX), Mermaid 다이어그램, 문서 폴더의 로컬 이미지
- HTML · PDF · 이미지 · 워드 문서 뷰어, ⌘E로 원문 편집
- 내장 터미널 패널과 Claude Code 실행
- ⌘P 빠른 열기, ⇧⌘F 폴더 본문 검색, 멀티 리네임
- 테마 4종(후원자 테마 8종 별도), 한국어 · 영어, Sparkle 자동 업데이트

설치 후에는 새 버전을 자동으로 받습니다(도움말 ▸ 업데이트 확인…으로 바로 확인 가능).

## 후원

Mac Commander는 모든 기능이 무료입니다. 도움이 되었다면 후원으로 개발을 응원해 주세요.

- 💖 [GitHub Sponsors](https://github.com/sponsors/codegeargit) — 월 정기 · 일회성
- ☕ [Buy Me a Coffee](https://buymeacoffee.com/codegear)

후원자 키가 있으면 기능은 그대로 두고 **후원자 테마 8종**(Nord · Dracula · Gruvbox · Catppuccin · Everforest · Solarized · Rosé Pine)과 **후원자 배지**가 열립니다. 키 발급은 준비 중입니다. 이름 공개에 동의한 후원자는 앱 정보(About) 창에 이름을 올립니다.

## 직접 빌드하기

요구 사항:

- macOS 14.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

`.xcodeproj`와 `Sources/Info.plist`는 `project.yml`에서 생성되므로 직접 고치지 않습니다.

```bash
xcodegen generate
open MacCommander.xcodeproj
```

`project.yml`의 `DEVELOPMENT_TEAM`은 공식 빌드의 서명 Team입니다. 직접 빌드할 때는 Xcode ▸ Signing & Capabilities에서 본인 Team을 고르거나 이 값을 바꾸세요.

커맨드라인 빌드:

```bash
xcodebuild -project MacCommander.xcodeproj \
  -scheme MacCommander -configuration Debug build
```

수정한 빌드를 배포하려면 [상표 정책](TRADEMARK.md)에 따라 앱 이름·아이콘·번들 ID·업데이트 주소를 바꿔야 합니다.

## 기여하기

버그 제보와 제안은 [이슈](https://github.com/codegeargit/mac-commander/issues)로 남겨 주세요. PR을 보내기 전에 [기여 안내](CONTRIBUTING.md)를 읽어 주세요. 첫 PR에는 [CLA](CLA.md) 서명이 필요합니다.

## 라이선스

Copyright © 2026 CodeGear

이 프로그램은 자유 소프트웨어입니다. [GNU General Public License 버전 3](LICENSE)(GPL-3.0-only)의 조건에 따라 재배포하거나 수정할 수 있습니다. 이 프로그램은 유용하게 쓰이길 바라며 배포되지만, 상품성이나 특정 목적 적합성에 대한 묵시적 보증을 포함해 **어떠한 보증도 하지 않습니다.**

- "Mac Commander" 이름과 앱 아이콘은 GPL 적용 대상이 아닙니다 — [TRADEMARK.md](TRADEMARK.md)
- 앱에 포함된 서드파티 오픈소스의 고지는 앱의 **도움말 ▸ 오픈소스 라이선스**와 `Sources/Resources/licenses/`에 있습니다

---

## 메인테이너용

### 로컬 설치

Release로 빌드해 `/Applications`에 설치합니다(Apple Development 자동 서명).

```bash
./scripts/install.sh          # 빌드 + 설치 + 실행
./scripts/install.sh --no-run # 실행은 생략
```

### 배포 (GitHub Releases)

App Store가 아닌 **GitHub 직접 배포**를 씁니다. 임베디드 터미널 때문에 App Sandbox를 해제해서 App Store에는 낼 수 없습니다. Developer ID 서명과 Apple 공증을 거쳐 `.dmg`를 만듭니다.

준비물(최초 1회):

1. **Developer ID Application 인증서** — Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ `+`
2. **App-specific password** — appleid.apple.com ▸ 로그인 및 보안 ▸ 앱 암호
3. **notary 자격증명 저장**:

   ```bash
   xcrun notarytool store-credentials "MC_NOTARY" \
     --apple-id "<apple-id>" --team-id "<team-id>" --password "<app-password>"
   ```

빌드 → 서명 → 공증 → staple → `.dmg` → appcast 서명 → GitHub Release 발행:

```bash
./scripts/release.sh               # 전 과정 자동 (배포까지)
./scripts/release.sh --no-notarize # 서명까지만(로컬 확인용, 배포 안 함)
```

`project.yml`의 버전을 올리고 실행하면 공개 배포 저장소 [mac-commander-releases](https://github.com/codegeargit/mac-commander-releases)에 dmg와 Sparkle appcast가 발행되고, 기존 사용자 앱이 자동 업데이트로 받습니다. appcast 서명용 EdDSA 개인키는 리포에 없으며 메인테이너의 Keychain에만 있습니다.
