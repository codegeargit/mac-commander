#!/usr/bin/env bash
#
# 마크다운 뷰어(WKWebView)에서 쓰는 오프라인 JS/CSS 자산을 내려받아
# Sources/Resources/ 에 생성한다.
#
#   - marked.min.js            : 마크다운 → HTML 변환
#   - katex.min.js             : LaTeX 수식 렌더링
#   - katex-auto-render.min.js : 본문에서 $...$ / $$...$$ 구분자를 찾아 렌더
#   - katex-inlined.css        : KaTeX CSS. woff2 폰트를 base64 data-URI로 인라인.
#
# 폰트를 인라인하는 이유: WKWebView loadHTMLString의 baseURL로는 CSS가 참조하는
# 폰트 상대경로(fonts/KaTeX_*.woff2)가 안정적으로 로드되지 않는다. 폰트를 CSS에
# data:font/woff2 로 직접 박아 넣으면 네트워크·경로 의존 없이 항상 렌더된다.
#
# 재현 가능하도록 버전을 고정한다. 자산이 바뀌면 이 스크립트를 다시 실행하고
# 결과 파일을 커밋한다.

set -euo pipefail

KATEX_VERSION="0.16.11"
MARKED_VERSION="14.1.2"

CDN="https://cdn.jsdelivr.net/npm"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/Sources/Resources"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "리소스 폴더: $RES_DIR"
mkdir -p "$RES_DIR"

echo "· marked.min.js (v$MARKED_VERSION) 다운로드"
curl -fsSL "$CDN/marked@$MARKED_VERSION/marked.min.js" -o "$RES_DIR/marked.min.js"

echo "· katex.min.js (v$KATEX_VERSION) 다운로드"
curl -fsSL "$CDN/katex@$KATEX_VERSION/dist/katex.min.js" -o "$RES_DIR/katex.min.js"

echo "· katex auto-render (v$KATEX_VERSION) 다운로드"
curl -fsSL "$CDN/katex@$KATEX_VERSION/dist/contrib/auto-render.min.js" -o "$RES_DIR/katex-auto-render.min.js"

echo "· katex.min.css + 폰트 다운로드"
curl -fsSL "$CDN/katex@$KATEX_VERSION/dist/katex.min.css" -o "$TMP_DIR/katex.css"

# katex.css가 참조하는 woff2 폰트를 모두 받아 base64로 인라인.
# CSS 안의 url(fonts/KaTeX_Xxx.woff2) 형태를 data:font/woff2;base64,... 로 치환한다.
# (woff / ttf 폴백은 제거 — WKWebView는 woff2를 지원하므로 woff2만 남기면 용량이 준다.)
mkdir -p "$TMP_DIR/fonts"

# CSS에서 참조하는 woff2 파일 이름 목록 추출.
grep -oE 'fonts/KaTeX_[A-Za-z0-9-]+\.woff2' "$TMP_DIR/katex.css" \
  | sort -u \
  | while read -r fontpath; do
      fontfile="$(basename "$fontpath")"
      if [[ ! -f "$TMP_DIR/fonts/$fontfile" ]]; then
        echo "    폰트: $fontfile"
        curl -fsSL "$CDN/katex@$KATEX_VERSION/dist/fonts/$fontfile" -o "$TMP_DIR/fonts/$fontfile"
      fi
    done

# python으로 CSS를 파싱해 woff2 url()을 data-URI로 치환하고,
# 같은 @font-face 안의 woff/ttf 폴백 url()은 제거한다.
python3 - "$TMP_DIR/katex.css" "$TMP_DIR/fonts" "$RES_DIR/katex-inlined.css" <<'PY'
import base64, re, sys, os

css_path, fonts_dir, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
css = open(css_path, encoding="utf-8").read()

def inline_woff2(m):
    name = m.group(1)
    path = os.path.join(fonts_dir, name)
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")
    return "url(data:font/woff2;base64,%s) format(\"woff2\")" % b64

# url(fonts/KaTeX_Xxx.woff2) format("woff2")  →  data-URI
css = re.sub(
    r'url\(fonts/(KaTeX_[A-Za-z0-9-]+\.woff2)\)\s*format\("woff2"\)',
    inline_woff2,
    css,
)

# 남은 woff/ttf 폴백 참조 제거: ,url(fonts/....woff) format("woff") 등.
css = re.sub(r',\s*url\(fonts/[^)]+\)\s*format\("(?:woff|truetype)"\)', "", css)

with open(out_path, "w", encoding="utf-8") as f:
    f.write(css)

n = css.count("data:font/woff2;base64,")
print("    인라인된 woff2 폰트 수: %d" % n)
if n == 0:
    sys.exit("ERROR: 폰트가 하나도 인라인되지 않았습니다. CSS 형식을 확인하세요.")
PY

echo ""
echo "완료. 생성된 파일:"
ls -la "$RES_DIR"/marked.min.js "$RES_DIR"/katex.min.js \
       "$RES_DIR"/katex-auto-render.min.js "$RES_DIR"/katex-inlined.css
