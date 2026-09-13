#!/usr/bin/env bash
#
# Mac Commander를 GitHub 직접 배포용으로 빌드 → Developer ID 서명
# → Apple 공증(notarize) → staple → .dmg 생성한다.
#
# App Store가 아닌 GitHub Releases 배포 전용. 결과물(.dmg)은 어떤 Mac에서도
# 더블클릭으로 실행된다(Gatekeeper 통과).
#
# 준비물(최초 1회):
#   1) Developer ID Application 인증서
#      Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
#   2) App-specific password (appleid.apple.com > 로그인 및 보안 > 앱 암호)
#   3) notary 자격증명을 키체인에 저장:
#      xcrun notarytool store-credentials "MC_NOTARY" \
#        --apple-id "<your-apple-id>" --team-id "W6WJJ8PJPM" --password "<app-password>"
#
# 사용법:
#   ./scripts/release.sh                 # 빌드+서명+공증+dmg (권장)
#   ./scripts/release.sh --no-notarize   # 서명까지만(공증/staple 생략, 로컬 확인용)
#   NOTARY_PROFILE=다른이름 ./scripts/release.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# .env가 있으면 읽어들인다(Drive 자격증명 등). .gitignore로 커밋에서 제외됨.
if [[ -f "$PROJECT_DIR/.env" ]]; then
  set -a; source "$PROJECT_DIR/.env"; set +a
fi

PROJECT="MacCommander.xcodeproj"
SCHEME="MacCommander"
APP_NAME="MacCommander.app"
TEAM_ID="W6WJJ8PJPM"
NOTARY_PROFILE="${NOTARY_PROFILE:-MC_NOTARY}"

# Sparkle 자동 업데이트 배포.
# dmg + appcast.xml 을 공개 배포 리포(mac-commander-releases)의 GitHub Release에 올린다.
# 앱의 SUFeedURL 이 이 리포의 releases/latest/download/appcast.xml 을 가리킨다.
# gh CLI는 codegeargit 계정이어야 한다(dukehabit이면 404).
RELEASE_REPO="${RELEASE_REPO:-codegeargit/mac-commander-releases}"

BUILD_DIR="$PROJECT_DIR/build/dist"
DIST_DIR="$PROJECT_DIR/dist"
BUILT_APP="$BUILD_DIR/$APP_NAME"

NOTARIZE=1
for arg in "$@"; do
  case "$arg" in
    --no-notarize) NOTARIZE=0 ;;
    *) echo "알 수 없는 옵션: $arg"; exit 1 ;;
  esac
done

# ── 0. Developer ID 인증서 확인 ────────────────────────────────────────────
echo "▶ 0/6  Developer ID Application 인증서 확인"
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')"
if [[ -z "$SIGN_ID" ]]; then
  cat <<'MSG'
✗ "Developer ID Application" 인증서가 없습니다.

  배포용 서명에는 개발용("Apple Development")이 아닌 Developer ID 인증서가 필요합니다.
  발급: Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application

  발급 후 다시 실행하세요.
MSG
  exit 1
fi
echo "  서명 ID: $SIGN_ID"

# ── 1. XcodeGen ────────────────────────────────────────────────────────────
echo "▶ 1/6  Xcode 프로젝트 생성 (xcodegen)"
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
else
  echo "  xcodegen이 없어 기존 .xcodeproj를 사용합니다."
fi

# ── 2. Release 빌드 (Developer ID 서명) ────────────────────────────────────
echo "▶ 2/6  Release 빌드 + Developer ID 서명"
rm -rf "$BUILD_DIR"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  -allowProvisioningUpdates \
  build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "✗ 빌드 산출물을 찾을 수 없습니다: $BUILT_APP"; exit 1
fi

# ── 2.5 Sparkle 중첩 번들 재서명 ────────────────────────────────────────────
# SPM artifact의 Sparkle.framework는 Sparkle 팀 인증서로 서명되어 온다.
# xcodebuild는 임베드 시 이를 재서명하지 않아 공증이 Invalid로 거부된다
# ("not signed with a valid Developer ID", "no secure timestamp").
# 중첩 번들을 안쪽부터 바깥쪽 순서로 Developer ID + timestamp + hardened
# runtime 으로 재서명한다. --deep 은 XPC 서비스를 망가뜨리므로 쓰지 않는다.
echo "▶ 2.5  Sparkle 중첩 번들 재서명"
SPARKLE_FW="$BUILT_APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
  SIGN_FLAGS=(--force --sign "$SIGN_ID" --timestamp --options runtime)
  # 1) XPC 서비스 (가장 안쪽)
  for xpc in "$SPARKLE_FW/Versions/B/XPCServices/"*.xpc; do
    [[ -e "$xpc" ]] && codesign "${SIGN_FLAGS[@]}" "$xpc"
  done
  # 2) Updater.app / Autoupdate 실행 파일
  [[ -e "$SPARKLE_FW/Versions/B/Updater.app" ]] && \
    codesign "${SIGN_FLAGS[@]}" "$SPARKLE_FW/Versions/B/Updater.app"
  [[ -e "$SPARKLE_FW/Versions/B/Autoupdate" ]] && \
    codesign "${SIGN_FLAGS[@]}" "$SPARKLE_FW/Versions/B/Autoupdate"
  # 3) 프레임워크 자체
  codesign "${SIGN_FLAGS[@]}" "$SPARKLE_FW"
  # 4) 중첩 서명이 바뀌었으므로 메인 앱을 entitlements 유지한 채 재서명
  codesign "${SIGN_FLAGS[@]}" \
    --entitlements "$PROJECT_DIR/Sources/MacCommander.entitlements" \
    "$BUILT_APP"
  echo "  Sparkle 재서명 완료 ✅"
else
  echo "  Sparkle.framework 없음(재서명 생략)"
fi

# ── 3. 서명 재확인(공증 요건: Hardened Runtime + timestamp) ────────────────
echo "▶ 3/6  서명 검증"
# --deep 는 쓰지 않는다. Sparkle.framework의 중첩 번들(XPCServices/Updater.app)에서
# --deep 검증은 오탐을 낼 수 있다. 각 번들은 xcodebuild가 개별 서명하므로
# 최상위 검증만으로 충분하다(공증이 전체 무결성을 다시 확인한다).
codesign --verify --strict "$BUILT_APP" && echo "  서명 유효 ✅"
codesign -dv "$BUILT_APP" 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier|flags=" | sed 's/^/  /'

# ── 4. .dmg 생성 ───────────────────────────────────────────────────────────
echo "▶ 4/6  .dmg 생성"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$BUILT_APP/Contents/Info.plist" 2>/dev/null || echo "dev")"
mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/MacCommander-$VERSION.dmg"
rm -f "$DMG_PATH"

# /Applications 심볼릭 링크를 포함한 스테이징 폴더로 dmg를 만든다(드래그 설치 UX).
STAGE="$(mktemp -d)"
cp -R "$BUILT_APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Mac Commander" \
  -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGE"
echo "  생성: $DMG_PATH"

# dmg도 서명(공증 대상). 앱은 이미 서명됨.
codesign --force --sign "$SIGN_ID" --timestamp "$DMG_PATH"

if [[ "$NOTARIZE" -eq 0 ]]; then
  echo "▶ 공증 생략(--no-notarize). 로컬 확인용으로만 사용하세요."
  echo "✅ 완료(서명만): $DMG_PATH"
  exit 0
fi

# ── 5. 공증(notarize) ──────────────────────────────────────────────────────
echo "▶ 5/6  Apple 공증 (notarytool, 수 분 소요)"
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  cat <<MSG
✗ notary 자격증명 프로필 "$NOTARY_PROFILE" 이(가) 없습니다.

  최초 1회 저장이 필요합니다:
    xcrun notarytool store-credentials "$NOTARY_PROFILE" \\
      --apple-id "<your-apple-id>" --team-id "$TEAM_ID" --password "<app-specific-password>"

  (dmg는 이미 만들어졌습니다: $DMG_PATH — 저장 후 다시 실행하면 공증됩니다.)
MSG
  exit 1
fi
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

# ── 6. staple (티켓을 dmg에 부착 → 오프라인에서도 Gatekeeper 통과) ─────────
echo "▶ 6/6  staple"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH" && echo "  staple 유효 ✅"

echo ""
echo "✅ 배포 준비 완료: $DMG_PATH"

# ── 7. Sparkle appcast 생성 + GitHub Release 발행 ──────────────────────────
# generate_appcast 가 dist/ 의 dmg를 스캔해 EdDSA 서명한 appcast.xml 을 만든다.
# 개인키는 로그인 Keychain에 있다(generate_keys로 생성). 그 뒤 dmg+appcast를
# 공개 배포 리포의 태그 릴리스로 발행한다.
echo "▶ 7  Sparkle appcast 생성 + GitHub Release 발행"

# generate_appcast 바이너리 찾기(SPM artifacts). DerivedData 위치가 유동적이라 검색.
GEN_APPCAST="$(find "$PROJECT_DIR/build" ~/Library/Developer/Xcode/DerivedData \
  -path "*artifacts/sparkle/Sparkle/bin/generate_appcast" -type f 2>/dev/null | head -1)"

if [[ -z "$GEN_APPCAST" ]]; then
  echo "  ✗ generate_appcast 를 찾을 수 없습니다(Sparkle SPM artifacts 미해결)."
  echo "    먼저 한 번 빌드해 패키지를 resolve하세요. appcast/릴리스 발행을 건너뜁니다."
elif ! command -v gh >/dev/null 2>&1; then
  echo "  ✗ gh CLI가 없습니다. appcast는 만들되 릴리스 발행은 건너뜁니다."
else
  # 각 dmg의 다운로드 URL을 이번 태그의 릴리스 자산 절대 URL로 박는다.
  DL_PREFIX="https://github.com/$RELEASE_REPO/releases/download/v$VERSION/"
  # generate_appcast는 대상 폴더의 dmg를 "전부" 스캔하고, --download-url-prefix를
  # 모든 항목에 동일하게 붙인다. dist/ 에는 이전 버전 dmg도 있어, 그대로 스캔하면
  # 구버전 URL까지 이번 태그로 잘못 박힌다(404 유발). 그래서 이번 dmg만 담은
  # 임시 폴더에서 appcast를 만든다(full 업데이트만 쓰므로 단일 항목으로 충분).
  APPCAST_STAGE="$(mktemp -d)"
  cp "$DMG_PATH" "$APPCAST_STAGE/"
  # 개인키는 기본적으로 로그인 Keychain에서 읽는다. Keychain 접근이 안 되는
  # 환경을 위해 ~/secrets 백업 키가 있으면 --ed-key-file로 명시한다.
  ED_KEY_ARGS=()
  ED_KEY_FILE="$HOME/secrets/sparkle-ed-private.key"
  [[ -f "$ED_KEY_FILE" ]] && ED_KEY_ARGS=(--ed-key-file "$ED_KEY_FILE")
  "$GEN_APPCAST" "${ED_KEY_ARGS[@]}" --download-url-prefix "$DL_PREFIX" "$APPCAST_STAGE"
  APPCAST_PATH="$DIST_DIR/appcast.xml"
  if [[ ! -f "$APPCAST_STAGE/appcast.xml" ]]; then
    echo "  ✗ appcast.xml 생성 실패"; rm -rf "$APPCAST_STAGE"; exit 1
  fi
  cp "$APPCAST_STAGE/appcast.xml" "$APPCAST_PATH"
  rm -rf "$APPCAST_STAGE"
  # edSignature가 실제로 붙었는지 검증한다. 없으면 앱이 업데이트를 거부하므로 중단.
  # (dmg 안의 앱 Info.plist에 SUPublicEDKey가 있어야 서명이 붙는다.)
  if ! grep -q "edSignature" "$APPCAST_PATH"; then
    echo "  ✗ appcast에 edSignature가 없습니다. dmg 내부 앱에 SUPublicEDKey가"
    echo "    포함됐는지, 개인키(Keychain 또는 $ED_KEY_FILE)가 유효한지 확인하세요."
    exit 1
  fi
  echo "  appcast 생성(서명 확인됨): $APPCAST_PATH"

  # GitHub Release 발행(같은 태그가 있으면 자산만 덮어쓴다).
  TAG="v$VERSION"
  if gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
    echo "  기존 릴리스 $TAG 갱신: 자산 업로드(--clobber)"
    gh release upload "$TAG" "$DMG_PATH" "$APPCAST_PATH" \
      --repo "$RELEASE_REPO" --clobber
  else
    echo "  새 릴리스 $TAG 생성"
    gh release create "$TAG" "$DMG_PATH" "$APPCAST_PATH" \
      --repo "$RELEASE_REPO" \
      --title "Mac Commander $VERSION" \
      --notes "Mac Commander $VERSION 자동 업데이트 릴리스."
  fi
  echo "  ✅ GitHub Release 발행 완료: https://github.com/$RELEASE_REPO/releases/tag/$TAG"
  echo "     appcast: https://github.com/$RELEASE_REPO/releases/latest/download/appcast.xml"
fi

# Google Drive 업로드는 GitHub Releases 배포로 대체되어 제거했다(2026-07).
# 필요하면 scripts/upload_to_drive.py 를 수동 실행해 올릴 수 있다.
