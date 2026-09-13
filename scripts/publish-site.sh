#!/usr/bin/env bash
#
# 소개 페이지(site/)를 공개 배포 리포의 docs/ 로 밀어 넣는다.
# GitHub Pages가 그 폴더를 서빙한다 → https://codegeargit.github.io/mac-commander-releases/
#
# 버전 문자열(다운로드 링크, 헤더, 푸터)은 project.yml의 값으로 맞춰서 올리므로
# site/index.html 을 직접 손볼 필요는 없다.
#
#   ./scripts/publish-site.sh            # 커밋 + 푸시
#   ./scripts/publish-site.sh --dry-run  # 치환 결과만 확인, 푸시 안 함
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="$PROJECT_DIR/site"
RELEASE_REPO="${RELEASE_REPO:-codegeargit/mac-commander-releases}"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

VERSION="$(grep -m1 'CFBundleShortVersionString:' "$PROJECT_DIR/project.yml" | sed 's/.*"\(.*\)".*/\1/')"
BUILD="$(grep -m1 'CFBundleVersion:' "$PROJECT_DIR/project.yml" | sed 's/.*"\(.*\)".*/\1/')"
[[ -n "$VERSION" && -n "$BUILD" ]] || { echo "❌ project.yml에서 버전을 못 읽었다"; exit 1; }
echo "▶ 버전 $VERSION ($BUILD) 로 페이지를 맞춘다"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp -R "$SITE_DIR" "$WORK/site"
# 버전이 박힌 자리들: 다운로드 URL, dmg 파일명, 버튼 문구, 헤더·푸터의 "1.8 (9)".
sed -i '' \
  -e "s|/releases/download/v[0-9][0-9.]*/MacCommander-[0-9][0-9.]*\.dmg|/releases/download/v$VERSION/MacCommander-$VERSION.dmg|g" \
  -e "s|MacCommander-[0-9][0-9.]*\.dmg|MacCommander-$VERSION.dmg|g" \
  -e "s|>[0-9][0-9.]* 다운로드|>$VERSION 다운로드|g" \
  -e "s|[0-9][0-9.]* 다운로드 (\.dmg)|$VERSION 다운로드 (.dmg)|g" \
  -e "s|[0-9][0-9.]* ([0-9][0-9]*)|$VERSION ($BUILD)|g" \
  "$WORK/site/index.html"

if $DRY_RUN; then
  echo "— 치환된 줄 —"
  grep -nE "MacCommander-|다운로드 \(\.dmg\)|\($BUILD\)" "$WORK/site/index.html"
  echo "✅ dry-run 종료 (푸시 안 함)"
  exit 0
fi

# HTTPS는 gh 자격증명이 다른 계정으로 잡힐 수 있어 SSH로 붙는다(코드 리포 origin과 동일).
git clone --depth 1 "git@github.com:$RELEASE_REPO.git" "$WORK/repo" 2>/dev/null
mkdir -p "$WORK/repo/docs"
cp "$WORK/site/index.html" "$WORK/site/icon.png" "$WORK/repo/docs/"

cd "$WORK/repo"
git add docs   # 새 파일은 add 전에는 diff에 안 잡히므로 먼저 스테이징한다
if git diff --cached --quiet -- docs; then
  echo "✅ 바뀐 내용 없음 — 푸시 생략"
  exit 0
fi
# 공개 리포라 커밋 작성자가 그대로 드러난다. 전역 git 설정(회사 메일 등) 대신
# GitHub noreply 주소로 커밋한다. 바꾸려면 PUBLIC_GIT_EMAIL을 넘긴다.
PUBLIC_GIT_NAME="${PUBLIC_GIT_NAME:-CodeGear}"
PUBLIC_GIT_EMAIL="${PUBLIC_GIT_EMAIL:-3898070+codegeargit@users.noreply.github.com}"
git -c user.name="$PUBLIC_GIT_NAME" -c user.email="$PUBLIC_GIT_EMAIL" \
  commit -q -m "Publish landing page for $VERSION"
git push -q origin HEAD
echo "✅ 배포 완료: https://codegeargit.github.io/mac-commander-releases/"
