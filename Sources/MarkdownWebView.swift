import SwiftUI
import WebKit

/// 마크다운 본문 전체를 WKWebView로 렌더링하는 뷰어.
///
/// 기존에는 SwiftUI 네이티브 MarkdownUI로 그렸으나, MarkdownUI(cmark-gfm)는
/// LaTeX 수식($...$, $$...$$)을 지원하지 않아 `$\rightarrow$` 같은 입력이
/// 화살표(→)가 아니라 리터럴 텍스트로 표시됐다. 수식은 문단·표 셀 텍스트
/// 중간(인라인)에 나오는데 MarkdownUI 2.4.1은 인라인 커스터마이징이 제한적이라
/// 블록 단위 교체(mermaid 방식)로는 처리할 수 없다.
///
/// 그래서 문서 전체를 한 HTML 페이지로 만들어:
///   marked.js(마크다운→HTML) + KaTeX(수식) + mermaid(다이어그램)
/// 를 오프라인 번들 자산으로 함께 렌더한다. 테마 색은 CSS로 재현한다.
struct MarkdownWebView: View {
    /// 마크다운 원문.
    let content: String
    /// 문서 파일. 상대 경로 이미지·링크(`![](images/foo.png)`)를 해석하는 기준 폴더이자,
    /// 스크롤 위치를 이어 붙일 때 쓰는 문서 식별자다.
    let fileURL: URL?
    /// 본문 기준 폰트 크기(뷰어 폰트 컨트롤과 동기화).
    let fontSize: CGFloat
    /// 현재 테마 색 모음(HTML/CSS로 재현).
    let colors: ColorSet
    /// 다크 계열 여부(mermaid 내장 테마 선택).
    let isDark: Bool
    /// 이 문서에서 읽던 위치(0~1)를 알려주는 제공자.
    /// 값이 스크롤마다 바뀌므로 프로퍼티로 받으면 낡은 값이 박히게 되어 클로저로 받는다.
    let scrollRatio: () -> Double
    /// 읽던 위치가 바뀔 때 호출 — 문서별로 기억해 두기 위함.
    let onScroll: (Double) -> Void
    /// 문서 안의 로컬 문서 링크(`[다음](other.md)`)를 클릭했을 때 호출 — 문서 간 이동.
    let onOpenFile: (URL) -> Void
    /// 문서 내 찾기 요청(⌘F 바에서 내려온다). nil이면 대기.
    let findRequest: FindRequest?
    /// 검색 결과 유무를 찾기 바에 알린다.
    let onFindResult: (Bool) -> Void

    var body: some View {
        MarkdownWebViewRepresentable(
            content: content,
            fileURL: fileURL,
            fontSize: fontSize,
            colors: colors,
            isDark: isDark,
            scrollRatio: scrollRatio,
            onScroll: onScroll,
            onOpenFile: onOpenFile,
            findRequest: findRequest,
            onFindResult: onFindResult
        )
    }
}

/// marked/KaTeX/mermaid를 로드해 마크다운을 렌더하는 WKWebView 래퍼(AppKit 브릿지).
private struct MarkdownWebViewRepresentable: NSViewRepresentable {
    let content: String
    let fileURL: URL?
    let fontSize: CGFloat
    let colors: ColorSet
    let isDark: Bool
    let scrollRatio: () -> Double
    let onScroll: (Double) -> Void
    let onOpenFile: (URL) -> Void
    let findRequest: FindRequest?
    let onFindResult: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        // JS → Swift 브릿지: 렌더 오류 로그와 스크롤 위치 전달.
        controller.add(context.coordinator, name: "mdBridge")
        config.userContentController = controller
        // 상대 경로 이미지(`![](./images/a.png)`)를 문서 폴더에서 읽어 오기 위한 스킴.
        // file:// baseURL로는 웹뷰가 로컬 파일을 하위 리소스로 읽지 못한다.
        config.setURLSchemeHandler(
            context.coordinator.localResourceHandler,
            forURLScheme: MarkdownLocalResource.scheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        syncCallbacks(context.coordinator)
        webView.navigationDelegate = context.coordinator
        // 트랙패드 두 손가락 핀치 확대(WKWebView 기본값은 꺼져 있다).
        // 목차를 포함해 화면 전체를 그대로 늘리는 합성 확대라 손가락을 그대로 따라온다.
        // 본문에만 CSS 배율을 주면 목차 자리는 지킬 수 있지만, 배율이 바뀔 때마다
        // 문서 전체가 다시 배치되어 눈에 띄게 느려진다.
        webView.allowsMagnification = true
        // 배경을 투명하게 두어 뷰어 배경색(HTML body 배경)이 그대로 보이게 한다.
        webView.setValue(false, forKey: "drawsBackground")

        load(webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // 콜백은 매 갱신마다 새로 만들어지므로(패널·문서를 캡처) 항상 최신으로 바꿔 둔다.
        syncCallbacks(context.coordinator)
        // 내용·테마가 바뀌면 다시 로드한다. 같은 값이면 건너뛴다.
        let key = context.coordinator.key(content: content, isDark: isDark, colors: colors)
        if key != context.coordinator.lastKey {
            load(webView, context: context)
        } else {
            // 글자 크기는 문서를 다시 그리지 않고 CSS만 바꾼다.
            context.coordinator.applyFontSize(fontSize, in: webView)
        }
        context.coordinator.runFindIfNeeded(findRequest, in: webView)
    }

    private func syncCallbacks(_ coordinator: Coordinator) {
        coordinator.onOpenFile = onOpenFile
        coordinator.onScroll = onScroll
        coordinator.onFindResult = onFindResult
    }

    private func load(_ webView: WKWebView, context: Context) {
        context.coordinator.lastKey = context.coordinator.key(
            content: content, isDark: isDark, colors: colors)
        // 새로 만드는 HTML에는 지금 글자 크기가 이미 들어간다(아래 MarkdownDocument.html).
        context.coordinator.lastFontSize = fontSize
        context.coordinator.documentWillReload()
        // 폰트·테마를 바꾸거나 편집을 마치고 돌아올 때마다 문서를 통째로 다시 그린다.
        // 읽던 위치를 함께 넘겨 문서 처음으로 튀지 않게 한다.
        let html = MarkdownDocument.html(
            content: content, fontSize: fontSize, colors: colors, isDark: isDark,
            scrollRatio: scrollRatio())
        // baseURL: 이미지·링크 상대 경로 해석용 문서 폴더. 자산은 HTML에 인라인되므로
        // 자산 로딩엔 baseURL이 필요 없다. file:// 대신 mdlocal:// 스킴을 쓰는 이유는
        // MarkdownLocalResource 주석 참고 — file://이면 이미지가 로드되지 않는다.
        let baseURL = fileURL
            .map { $0.deletingLastPathComponent() }
            .flatMap(MarkdownLocalResource.url(for:))
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        /// 문서 폴더의 이미지 등을 웹뷰에 넘겨주는 스킴 핸들러.
        /// 웹뷰 설정이 붙들고 있으므로 코디네이터와 수명을 같이 한다.
        let localResourceHandler = MarkdownLocalResourceHandler()
        var lastKey: String = ""
        /// 마지막으로 웹뷰에 반영한 본문 글자 크기(같으면 JS를 다시 실행하지 않는다).
        var lastFontSize: CGFloat = 0
        /// 로컬 문서 링크를 뷰어에서 열기 위한 콜백(패널을 캡처하고 있다).
        var onOpenFile: ((URL) -> Void)?
        /// 읽던 위치를 문서별로 기억해 두기 위한 콜백.
        var onScroll: ((Double) -> Void)?
        /// 검색 결과 유무를 찾기 바에 알리는 콜백.
        var onFindResult: ((Bool) -> Void)?
        /// 마지막으로 실행한 검색 요청(같은 요청을 두 번 실행하지 않기 위해).
        private var lastFindRequest: FindRequest?
        /// 렌더가 끝나기 전에 들어온 검색 요청. 본문 검색 결과에서 문서를 열면
        /// 파일 열기와 검색이 거의 동시에 오므로, 본문이 그려진 뒤로 미뤄야 한다.
        private var pendingFindRequest: FindRequest?
        /// 지금 로드한 문서의 마크다운 파싱이 끝났는지(JS가 알려준다).
        private var isDocumentReady = false

        /// 문서를 다시 로드할 때 호출 — 렌더 완료 신호를 다시 기다린다.
        func documentWillReload() {
            isDocumentReady = false
        }

        /// 새 검색 요청이면 웹뷰 검색을 실행한다.
        /// 일련번호가 붙어 있어 같은 문자열로 "다음"을 반복해도 매번 새 요청으로 들어온다.
        func runFindIfNeeded(_ request: FindRequest?, in webView: WKWebView) {
            guard let request, request != lastFindRequest else { return }
            lastFindRequest = request
            guard !request.query.isEmpty else { return }
            guard isDocumentReady else {
                pendingFindRequest = request
                return
            }
            execute(request, in: webView)
        }

        /// 렌더가 끝난 뒤 밀어둔 검색을 실행한다.
        func runPendingFind(in webView: WKWebView) {
            guard let request = pendingFindRequest else { return }
            pendingFindRequest = nil
            execute(request, in: webView)
        }

        private func execute(_ request: FindRequest, in webView: WKWebView) {
            let config = WKFindConfiguration()
            config.backwards = !request.forward
            config.caseSensitive = false
            config.wraps = true   // 끝에 닿으면 처음으로 돌아가 계속 찾는다
            webView.find(request.query, configuration: config) { [weak self] result in
                self?.onFindResult?(result.matchFound)
            }
        }

        /// JS가 본문 파싱을 끝냈다고 알려왔을 때.
        fileprivate func markDocumentReady(in webView: WKWebView?) {
            isDocumentReady = true
            if let webView { runPendingFind(in: webView) }
        }

        /// 문서를 다시 그려야 하는지 판단하는 키. 글자 크기는 CSS만 바꿔 처리하므로
        /// 여기에 넣지 않는다(넣으면 한 단계 키울 때마다 문서 전체가 다시 렌더된다).
        func key(content: String, isDark: Bool, colors: ColorSet) -> String {
            "\(isDark)-\(colors.viewerBackground.hexString)-\(content.hashValue)"
        }

        /// 글자 크기만 바뀌었을 때 — 문서를 다시 그리지 않고 body의 font-size만 갱신한다.
        /// 제목·코드·수식 크기는 모두 em 상대 단위라 이 한 줄로 본문 전체가 따라 커진다.
        func applyFontSize(_ size: CGFloat, in webView: WKWebView) {
            guard Int(size) != Int(lastFontSize) else { return }
            lastFontSize = size
            webView.evaluateJavaScript(
                "document.body.style.fontSize = '\(Int(size))px';", completionHandler: nil)
        }

        /// 문서 안의 링크 클릭 처리.
        ///
        /// 정책을 주지 않으면 WKWebView가 **그 자리에서 대상 페이지로 이동**해
        /// 뷰어 패널이 브라우저처럼 바뀌고 문서로 되돌아올 방법이 없다.
        ///
        /// - 뷰어가 렌더할 수 있는 로컬 파일 → 이 패널에서 그 문서를 연다(문서 간 이동).
        /// - 그 밖의 로컬 파일 → 시스템 기본 앱에 맡긴다(바이너리를 평문으로 열면 깨져 보인다).
        /// - 폴더 → Finder에서 보여준다.
        /// - 외부 주소(http·mailto 등) → 기본 브라우저로 넘긴다.
        ///
        /// 문서 내 앵커(`#제목`)는 HTML 쪽 스크립트가 `preventDefault`로 처리하므로
        /// 이 메서드까지 오지 않는다.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 최초 loadHTMLString(.other)은 허용해야 문서가 그려진다.
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)

            // 문서 폴더 기준 상대 링크는 baseURL을 따라 mdlocal:// 스킴으로 들어온다.
            // 아래 판단은 모두 실제 파일 경로를 봐야 하므로 file://로 되돌린다.
            let target = MarkdownLocalResource.fileURL(for: url) ?? url

            guard target.isFileURL else {
                NSWorkspace.shared.open(target)
                return
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory)
            else {
                // 깨진 상대 링크. 조용히 무시하되 로그는 남긴다.
                NSLog("[MarkdownWebView] broken link: \(target.path)")
                return
            }
            if isDirectory.boolValue {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: target.path)
            } else if FileNode.defaultVisibleExtensions.contains(target.pathExtension.lowercased()) {
                onOpenFile?(target)
            } else {
                NSWorkspace.shared.open(target)
            }
        }

        /// JS 브릿지 수신. 렌더 오류는 로깅만 하고(화면엔 이미 부분 렌더가 보인다),
        /// 스크롤 위치는 문서별 기억으로 넘긴다.
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if let error = body["error"] as? String {
                NSLog("[MarkdownWebView] render error: \(error)")
            }
            if let ratio = body["scroll"] as? Double {
                onScroll?(ratio)
            }
            if body["ready"] as? Bool == true {
                markDocumentReady(in: message.webView)
            }
        }
    }
}

// MARK: - HTML 문서 생성

/// 마크다운 원문 + 자산 + 테마 CSS를 하나의 HTML 문서로 조립한다.
enum MarkdownDocument {
    static func html(content: String, fontSize: CGFloat, colors: ColorSet, isDark: Bool,
                     scrollRatio: Double = 0) -> String {
        // NaN·무한대가 JS 리터럴로 새어 나가면 스크립트 전체가 죽는다.
        let restoreRatio = scrollRatio.isFinite ? min(max(scrollRatio, 0), 1) : 0
        let css = themeCSS(fontSize: fontSize, colors: colors)
        let katexCSS = MathAsset.katexCSS
        let markedTag = MathAsset.markedScriptTag
        let katexTag = MathAsset.katexScriptTag
        let autoRenderTag = MathAsset.autoRenderScriptTag
        let mermaidTag = MermaidAsset.scriptTag
        let mermaidTheme = isDark ? "dark" : "default"
        // 원문은 JSON.stringify 결과로 안전하게 주입한다. 백틱·달러·역슬래시가
        // 그대로 보존되어야 하며(달러는 수식 구분자), JS 문자열 리터럴로는
        // 이스케이프가 까다롭다. JSON 인코딩이 가장 안전하다.
        let mdJSON = jsonEncoded(content)

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(katexCSS)
        </style>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <div id="content"></div>
        \(markedTag)
        \(katexTag)
        \(autoRenderTag)
        \(mermaidTag)
        <script>
          function report(payload) {
            try { window.webkit.messageHandlers.mdBridge.postMessage(payload); } catch (e) {}
          }

          // 읽던 위치를 앱에 알린다. 폰트·테마를 바꾸거나 편집을 오갈 때
          // 문서를 다시 그리는데, 그때 이 값으로 위치를 이어 붙인다.
          // 아래 렌더 파이프라인보다 먼저 등록해 둔다(렌더 도중 발생하는 스크롤도 놓치지 않게).
          var ignoreScrollUntil = 0;
          var scrollTimer = null;
          window.addEventListener("scroll", function () {
            if (scrollTimer || Date.now() < ignoreScrollUntil) return;
            scrollTimer = setTimeout(function () {
              scrollTimer = null;
              const max = document.documentElement.scrollHeight - window.innerHeight;
              report({ scroll: max > 0 ? window.pageYOffset / max : 0 });
            }, 120);
          }, { passive: true });

          (async function () {
            const md = \(mdJSON);
            const el = document.getElementById("content");
            try {
              // 1) 마크다운 → HTML (GFM: 표/체크박스/줄바꿈).
              marked.setOptions({ gfm: true, breaks: false });
              el.innerHTML = marked.parse(md);
            } catch (e) {
              report({ error: "marked: " + String(e && e.message ? e.message : e) });
              el.textContent = md; // 최소한 원문이라도 보이게.
              report({ ready: true });   // 원문이라도 검색은 되게 한다.
              return;
            }

            // 1-0) `![](file:///…/a.png)`처럼 절대 경로를 file:// 로 적은 이미지는
            //      웹뷰가 로드하지 못한다(상대 경로는 baseURL 덕에 mdlocal:// 로 풀린다).
            //      같은 스킴으로 바꿔 주면 나머지 이미지와 똑같이 표시된다.
            try {
              el.querySelectorAll('img[src^="file://"]').forEach(function (img) {
                const path = img.getAttribute("src").replace(/^file:\\/\\/(localhost)?/, "");
                img.setAttribute("src", "\(MarkdownLocalResource.urlPrefix)" + path);
              });
            } catch (e) {
              report({ error: "images: " + String(e && e.message ? e.message : e) });
            }

            // 1-1) 제목에 앵커 id를 붙인다. marked는 v12에서 headerIds를 떼어냈으므로
            //      직접 붙이지 않으면 문서 목차(`[개요](#개요)`)가 전혀 동작하지 않는다.
            //      GitHub 규칙에 맞춰 소문자화 → 구두점 제거 → 공백을 하이픈으로.
            //      한글은 문자로 남으므로 `## 개요` → id="개요"가 된다.
            try {
              const seen = new Map();
              el.querySelectorAll("h1,h2,h3,h4,h5,h6").forEach(function (h) {
                if (h.id) return;
                const base = h.textContent.trim().toLowerCase()
                  .replace(/[^\\p{L}\\p{N}\\p{M}_\\s-]/gu, "")
                  .replace(/\\s+/g, "-") || "section";
                const n = seen.get(base) || 0;
                seen.set(base, n + 1);
                h.id = n === 0 ? base : base + "-" + n;
              });
            } catch (e) {
              report({ error: "anchors: " + String(e && e.message ? e.message : e) });
            }

            // 1-2) 같은 문서 안 앵커 이동은 여기서 처리한다. 그냥 두면 페이지 이동으로
            //      취급돼 Swift의 링크 정책까지 올라가므로, 스크롤만 하고 막는다.
            document.addEventListener("click", function (ev) {
              const a = ev.target && ev.target.closest ? ev.target.closest("a") : null;
              if (!a) return;
              const href = a.getAttribute("href");
              if (!href || href.charAt(0) !== "#") return;
              ev.preventDefault();
              let id = href.slice(1);
              try { id = decodeURIComponent(id); } catch (e) {}
              const target = document.getElementById(id) || document.getElementsByName(id)[0];
              if (target) target.scrollIntoView({ behavior: "smooth", block: "start" });
            });

            // 1-3) 오른쪽에 고정으로 붙는 목차. 제목이 둘 이상일 때만 만든다.
            //      항목은 `#id` 링크라 클릭하면 바로 위 1-2 리스너가 스크롤을 맡는다.
            try {
              const heads = Array.from(el.querySelectorAll("h1,h2,h3"));
              if (heads.length > 1) {
                const nav = document.createElement("nav");
                nav.id = "toc";
                const items = heads.map(function (h) {
                  const a = document.createElement("a");
                  a.className = "toc-" + h.tagName.toLowerCase();
                  a.href = "#" + encodeURIComponent(h.id);
                  a.textContent = h.textContent.trim();
                  a.title = a.textContent;   // 잘린 긴 제목은 툴팁으로 본다
                  nav.appendChild(a);
                  return a;
                });
                // 본문 뒤에 붙인다 — ⌘F 검색이 본문을 먼저 훑도록.
                document.body.appendChild(nav);
                document.body.classList.add("has-toc");

                // 지금 읽고 있는 섹션을 목차에서 짚어 준다.
                // 화면 위쪽 80px 선을 지난 마지막 제목이 현재 섹션.
                let activeIndex = -1;
                let ticking = false;
                function syncActive() {
                  const line = window.pageYOffset + 80;
                  let idx = 0;
                  for (let i = 0; i < heads.length; i++) {
                    if (heads[i].getBoundingClientRect().top + window.pageYOffset <= line) idx = i;
                    else break;
                  }
                  if (idx === activeIndex) return;
                  if (activeIndex >= 0) items[activeIndex].classList.remove("active");
                  activeIndex = idx;
                  const a = items[idx];
                  a.classList.add("active");
                  // 목차가 길어 활성 항목이 목차 밖으로 나가면 따라 굴린다.
                  // scrollIntoView는 본문까지 함께 움직일 수 있어 직접 계산한다.
                  const top = a.offsetTop;
                  const h = nav.clientHeight;
                  if (top < nav.scrollTop || top + a.offsetHeight > nav.scrollTop + h) {
                    nav.scrollTop = Math.max(0, top - h / 3);
                  }
                }
                window.addEventListener("scroll", function () {
                  if (ticking) return;
                  ticking = true;
                  requestAnimationFrame(function () { ticking = false; syncActive(); });
                }, { passive: true });
                syncActive();
              }
            } catch (e) {
              report({ error: "toc: " + String(e && e.message ? e.message : e) });
            }

            // 2) mermaid 코드블록 렌더. marked는 ```mermaid``` 를
            //    <pre><code class="language-mermaid"> 로 낸다. 이를 골라 SVG로 바꾼다.
            try {
              mermaid.initialize({ startOnLoad: false, theme: "\(mermaidTheme)",
                securityLevel: "strict" });
              const blocks = el.querySelectorAll("pre > code.language-mermaid");
              let i = 0;
              for (const code of blocks) {
                const def = code.textContent;
                const pre = code.parentElement;
                try {
                  const { svg } = await mermaid.render("mmd-" + (i++), def);
                  const wrap = document.createElement("div");
                  wrap.className = "mermaid-rendered";
                  wrap.innerHTML = svg;
                  pre.replaceWith(wrap);
                } catch (e) {
                  // 개별 다이어그램 실패는 원본 코드블록을 그대로 두고 넘어간다.
                  report({ error: "mermaid: " + String(e && e.message ? e.message : e) });
                }
              }
            } catch (e) {
              report({ error: "mermaid-init: " + String(e && e.message ? e.message : e) });
            }

            // 3) 수식 렌더. $$...$$ (display) 와 $...$ (inline), \\[..\\] \\(..\\) 지원.
            //    mermaid SVG 안의 텍스트는 건드리지 않도록 이미 위에서 교체를 끝냈다.
            try {
              renderMathInElement(el, {
                delimiters: [
                  { left: "$$", right: "$$", display: true },
                  { left: "\\\\[", right: "\\\\]", display: true },
                  { left: "$", right: "$", display: false },
                  { left: "\\\\(", right: "\\\\)", display: false }
                ],
                throwOnError: false,
                ignoredTags: ["script", "noscript", "style", "textarea", "pre", "code"]
              });
            } catch (e) {
              report({ error: "katex: " + String(e && e.message ? e.message : e) });
            }

            // 4) 읽던 위치로 되돌린다. 수식·다이어그램 렌더가 끝나 문서 높이가
            //    확정된 뒤여야 위치가 맞으므로 파이프라인의 마지막에 둔다.
            const restore = \(restoreRatio);
            if (restore > 0) {
              const max = document.documentElement.scrollHeight - window.innerHeight;
              if (max > 0) {
                // 복원 스크롤 자체가 아래 리스너를 깨워 어긋난 비율을 되돌려 보내는 걸 막는다.
                ignoreScrollUntil = Date.now() + 400;
                window.scrollTo(0, restore * max);
              }
            }

            // 5) 본문이 완전히 확정됐음을 앱에 알린다. 본문 검색 결과에서 문서를 열면
            //    파일 열기와 ⌘F 검색이 거의 동시에 오는데, 이 신호를 받은 뒤 검색해야
            //    빈 문서에서 찾다가 실패하지 않는다.
            report({ ready: true });
          })();
        </script>
        </body>
        </html>
        """
    }

    /// 문자열을 JS에 안전하게 주입할 JSON 리터럴로 인코딩한다.
    private static func jsonEncoded(_ s: String) -> String {
        // JSONEncoder는 최상위 문자열도 인코딩한다(withoutEscapingSlashes로 슬래시 보존).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? encoder.encode(s), let str = String(data: data, encoding: .utf8) {
            return str
        }
        // 극히 예외적 실패 시 빈 문자열로.
        return "\"\""
    }

    /// 현재 테마(ColorSet)와 폰트 크기로 본문 CSS를 만든다.
    /// 기존 MarkdownUI `retroCommander` 테마(MarkdownTheme.swift)의 색·여백·크기 규칙을
    /// HTML/CSS로 재현한다.
    private static func themeCSS(fontSize: CGFloat, colors: ColorSet) -> String {
        let base = Int(fontSize)
        // readingWidth(760)와 좌우/상하 여백은 기존 DocumentDetailView와 맞춘다.
        let readingWidth = Int(Metrics.readingWidth)
        // 우측 목차 폭. 본문 폰트를 키워도 목차는 작게 유지되므로 고정값으로 둔다.
        let tocWidth = 210

        let textPrimary = colors.textPrimary.hexString
        let textHeading = colors.textHeading.hexString
        let textFolder = colors.textFolder.hexString
        let textMuted = colors.textMuted.hexString
        let accent = colors.accent.hexString
        let accentDim = colors.accentDim.hexString
        let divider = colors.divider.hexString
        let codeBlockBg = colors.codeBlockBackground.hexString
        let codeInlineBg = colors.codeInlineBackground.hexString
        let panelBg = colors.panelBackground.hexString
        let selectBg = colors.selectBackground.hexString
        let selectFg = colors.selectForeground.hexString

        // 폰트 스택: 시스템 산세리프(한글 포함). 코드/수식은 별도.
        return """
        * { box-sizing: border-box; }
        html, body { margin: 0; padding: 0; background: transparent; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", "Apple SD Gothic Neo", sans-serif;
          font-size: \(base)px;
          line-height: 1.6;
          color: \(textPrimary);
          -webkit-text-size-adjust: 100%;
        }
        #content {
          max-width: \(readingWidth)px;
          margin: 0 auto;
          padding: 20px 24px 60px;
        }
        ::selection { background: \(selectBg); color: \(selectFg); }

        /* 문단·목록 여백 */
        p { margin: 0 0 16px; }
        ul, ol { margin: 4px 0 16px; padding-left: 1.6em; }
        li { margin-top: 0.4em; line-height: 1.55; }
        li > p { margin: 0; }

        /* 제목 */
        h1, h2, h3, h4, h5, h6 { font-weight: 700; line-height: 1.3; }
        h1 {
          font-size: 2em; color: \(textHeading);
          margin: 40px 0 10px; padding-bottom: 0.3em;
          border-bottom: 1px solid \(divider);
        }
        h2 {
          font-size: 1.5em; color: \(textHeading);
          margin: 34px 0 10px; padding-bottom: 0.3em;
          border-bottom: 1px solid \(divider);
        }
        h3 { font-size: 1.25em; color: \(textFolder); margin: 28px 0 8px; font-weight: 600; }
        h4 { font-size: 1.05em; color: \(textFolder); margin: 22px 0 6px; font-weight: 600; }
        h5, h6 { font-size: 1em; color: \(textFolder); margin: 18px 0 6px; font-weight: 600; }
        /* 첫 제목의 큰 위쪽 여백은 없앤다(문서 맨 위 빈 공간 방지). */
        #content > :first-child { margin-top: 0; }

        /* 볼드/링크 */
        strong, b { font-weight: 600; color: \(textHeading); }
        a { color: \(accent); text-decoration: none; }
        a:hover { text-decoration: underline; }

        /* 인라인 코드 */
        code {
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
          font-size: 0.9em;
          color: \(accent);
          background: \(codeInlineBg);
          padding: 0.15em 0.35em;
          border-radius: 4px;
        }
        /* 코드 블록 */
        pre {
          background: \(codeBlockBg);
          border-radius: 6px;
          padding: 12px;
          overflow-x: auto;
          margin: 8px 0;
        }
        pre code {
          background: none; color: \(textPrimary);
          padding: 0; border-radius: 0;
          font-size: 0.9em; line-height: 1.5;
        }

        /* 인용구 */
        blockquote {
          margin: 8px 0; padding-left: 12px;
          border-left: 3px solid \(accentDim);
          color: \(textMuted);
        }

        /* 표 */
        table {
          border-collapse: collapse;
          margin: 8px 0;
          width: auto;
          max-width: 100%;
        }
        th, td {
          border: 1px solid \(divider);
          padding: 9px 14px;
          text-align: left;
        }
        th { font-weight: 600; color: \(textFolder); background: \(codeBlockBg); }
        td { color: \(textPrimary); }
        tr:nth-child(even) td { background: \(codeBlockBg); }
        tr:nth-child(odd) td { background: \(panelBg); }

        /* 수평선 */
        hr { border: none; border-top: 1px solid \(divider); margin: 12px 0; }

        /* 이미지: 폭 넘치면 줄인다. */
        img { max-width: 100%; height: auto; }

        /* mermaid 렌더 결과: 가운데 정렬. */
        .mermaid-rendered { display: flex; justify-content: center; margin: 8px 0; }
        .mermaid-rendered svg { max-width: 100%; height: auto; }

        /* KaTeX display 수식이 넘칠 때 가로 스크롤 */
        .katex-display { overflow-x: auto; overflow-y: hidden; }

        /* 우측 목차(TOC).
           본문과 겹치지 않도록 body에 오른쪽 여백을 주고 그 자리에 고정한다.
           제목이 둘 이상일 때만 JS가 body.has-toc 를 붙인다. */
        body.has-toc { padding-right: \(tocWidth)px; }
        #toc {
          position: fixed;
          top: 0;
          right: 0;
          width: \(tocWidth)px;
          height: 100vh;
          overflow-y: auto;
          /* 목차 끝까지 굴렸을 때 본문으로 스크롤이 넘어가지 않게. */
          overscroll-behavior: contain;
          padding: 22px 12px 48px;
          border-left: 1px solid \(divider);
          font-size: 0.8em;
          line-height: 1.45;
        }
        #toc a {
          display: block;
          color: \(textMuted);
          text-decoration: none;
          padding: 3px 8px;
          border-radius: 4px;
          border-left: 2px solid transparent;
          /* 한글은 어절 단위로 끊고, 긴 영문 토큰만 강제로 자른다. */
          word-break: keep-all;
          overflow-wrap: anywhere;
        }
        #toc a.toc-h1 { color: \(textHeading); font-weight: 600; }
        #toc a.toc-h2 { padding-left: 16px; }
        #toc a.toc-h3 { padding-left: 28px; font-size: 0.95em; }
        #toc a:hover { color: \(accent); background: \(codeInlineBg); text-decoration: none; }
        #toc a.active { color: \(accent); border-left-color: \(accent); font-weight: 600; }
        #toc::-webkit-scrollbar { width: 6px; }
        #toc::-webkit-scrollbar-thumb { background: \(divider); border-radius: 3px; }
        /* 패널이 좁으면 본문을 살려야 하므로 목차를 접는다. */
        @media (max-width: \(readingWidth + tocWidth + 80)px) {
          #toc { display: none; }
          body.has-toc { padding-right: 0; }
        }
        """
    }
}

// MARK: - 자산 로더

/// 마크다운 뷰어가 쓰는 marked/KaTeX 자산을 번들에서 찾아 인라인한다.
/// mermaid는 기존 MermaidAsset을 그대로 재사용한다.
enum MathAsset {
    /// marked.min.js 를 <script>로 인라인(없으면 CDN 폴백).
    static let markedScriptTag: String = inlineScript(
        resource: "marked.min",
        cdn: "https://cdn.jsdelivr.net/npm/marked@14/marked.min.js")

    /// katex.min.js 를 <script>로 인라인.
    static let katexScriptTag: String = inlineScript(
        resource: "katex.min",
        cdn: "https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js")

    /// auto-render 확장을 <script>로 인라인.
    static let autoRenderScriptTag: String = inlineScript(
        resource: "katex-auto-render.min",
        cdn: "https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js")

    /// 폰트가 base64로 인라인된 KaTeX CSS 본문(스타일 태그 안에 넣을 순수 CSS).
    static let katexCSS: String = {
        if let url = Bundle.main.url(forResource: "katex-inlined", withExtension: "css"),
           let css = try? String(contentsOf: url, encoding: .utf8) {
            return css
        }
        // 폴백: CDN CSS를 @import (폰트는 CDN에서). 오프라인이면 수식 글리프가 깨질 수 있다.
        return #"@import url("https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css");"#
    }()

    /// 번들 JS를 읽어 <script>...</script> 문자열로 감싼다. 못 찾으면 CDN src 태그로.
    private static func inlineScript(resource: String, cdn: String) -> String {
        if let url = Bundle.main.url(forResource: resource, withExtension: "js"),
           let js = try? String(contentsOf: url, encoding: .utf8) {
            return "<script>\n\(js)\n</script>"
        }
        return "<script src=\"\(cdn)\"></script>"
    }
}

// MARK: - 색 → CSS hex

extension Color {
    /// SwiftUI Color를 `#RRGGBB` CSS 문자열로 변환한다(테마 색을 HTML에 넘길 때 사용).
    /// sRGB 컴포넌트를 NSColor 경유로 뽑는다.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
