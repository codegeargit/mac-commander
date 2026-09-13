#!/usr/bin/env bash
#
# Mac Commander를 Release로 빌드해 /Applications에 설치한다.
# Apple Development 인증서(project.yml의 DEVELOPMENT_TEAM)로 자동 서명.
#
# 사용법:
#   ./scripts/install.sh            # 빌드 + 설치 + 실행
#   ./scripts/install.sh --no-run   # 빌드 + 설치만(실행 안 함)
#   ./scripts/install.sh --no-open  # (별칭) 실행 안 함
#
set -euo pipefail

# 프로젝트 루트(이 스크립트의 상위 폴더)로 이동.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

PROJECT="MacCommander.xcodeproj"
SCHEME="MacCommander"
APP_NAME="MacCommander.app"
BUILD_DIR="$PROJECT_DIR/build/release"
DEST="/Applications/$APP_NAME"

RUN_AFTER=1
for arg in "$@"; do
  case "$arg" in
    --no-run|--no-open) RUN_AFTER=0 ;;
    *) echo "알 수 없는 옵션: $arg"; exit 1 ;;
  esac
done

echo "▶ 1/4  Xcode 프로젝트 생성 (xcodegen)"
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
else
  echo "  xcodegen이 없어 기존 .xcodeproj를 사용합니다. (brew install xcodegen 권장)"
fi

echo "▶ 2/4  Release 빌드 (자동 서명)"
rm -rf "$BUILD_DIR"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'platform=macOS' \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  -allowProvisioningUpdates \
  build

BUILT_APP="$BUILD_DIR/$APP_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "✗ 빌드 산출물을 찾을 수 없습니다: $BUILT_APP"
  exit 1
fi

echo "▶ 3/4  /Applications 에 설치"
# 실행 중이면 종료(설치본/개발본 모두).
osascript -e 'tell application "MacCommander" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST"
cp -R "$BUILT_APP" "$DEST"

echo "▶ 4/4  서명 검증"
codesign --verify --strict "$DEST" && echo "  서명 유효 ✅"
codesign -dv "$DEST" 2>&1 | grep -E "Authority=Apple Development|TeamIdentifier" | sed 's/^/  /'

if [[ "$RUN_AFTER" -eq 1 ]]; then
  echo "▶ 실행"
  open "$DEST"
fi

echo "✅ 설치 완료: $DEST"
