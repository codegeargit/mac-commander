import SwiftUI
import WebKit

/// HTML 파일(.html/.htm)을 브라우저처럼 그대로 렌더링하는 뷰어.
///
/// 파일을 `mdlocal://` 스킴으로 로드하므로, 문서가 참조하는 상대 경로의
/// CSS·이미지·스크립트도 같은 스킴을 타고 문서 폴더에서 읽힌다(읽기는 문서 폴더
/// 안으로 제한). 앱 테마 색과 무관하게 HTML 자체 스타일로 표시된다.
///
/// `loadFileURL`을 쓰지 않는 이유: 응답 인코딩을 지정할 수 없어, `<meta charset>`이
/// 없는 UTF-8 HTML을 WebKit이 로캘 기본 인코딩(EUC-KR)으로 풀어 한글이 깨진다.
/// 스킴 핸들러는 UTF-8로 읽히는 파일에 인코딩을 명시해 준다(MarkdownLocalResource 참고).
///
/// 편집 모드(⌘E)에서는 이 뷰가 아니라 TextEditor가 원문(태그)을 보여준다.
struct HTMLWebView: NSViewRepresentable {
    /// 렌더링할 HTML 파일 URL.
    let fileURL: URL
    /// 문서 내 찾기 요청(⌘F 바에서 내려온다). nil이면 대기.
    var findRequest: FindRequest?
    /// 검색 결과 유무를 찾기 바에 알린다.
    var onFindResult: ((Bool) -> Void)?
    /// 이 문서에서 읽던 위치(0~1). 다른 파일을 보고 돌아왔을 때 이어 보기 위함.
    /// 값이 스크롤마다 바뀌므로 프로퍼티로 받으면 낡은 값이 박히게 되어 클로저로 받는다.
    var scrollRatio: (URL) -> Double = { _ in 0 }
    /// 읽던 위치가 바뀔 때 호출 — 문서별로 기억해 두기 위함.
    var onScroll: ((Double, URL) -> Void)?
    /// 이 문서에서 마지막으로 본 주소 해시(`#3`). 프레젠테이션형 HTML은 지금 페이지를
    /// 해시에 적어 두므로, 돌아왔을 때 해시를 붙여 로드하면 같은 페이지가 열린다.
    var fragment: (URL) -> String? = { _ in nil }
    /// 주소 해시가 바뀔 때 호출 — 문서별로 기억해 두기 위함.
    var onFragment: ((String?, URL) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // JS → Swift 브릿지: 스크롤 위치 전달. 문서 자체 스크립트와 섞이지 않게
        // 메인 프레임에만 심는다.
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.bridgeName)
        controller.addUserScript(WKUserScript(
            source: Coordinator.scrollReporterJS,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController = controller
        config.setURLSchemeHandler(
            context.coordinator.localResourceHandler,
            forURLScheme: MarkdownLocalResource.scheme)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // 트랙패드 두 손가락 핀치 확대(WKWebView 기본값은 꺼져 있다).
        webView.allowsMagnification = true
        // 해시는 history.replaceState로만 바뀌기도 해(hashchange 이벤트가 안 난다)
        // 웹뷰 주소를 직접 지켜본다.
        context.coordinator.observeURL(of: webView)
        load(webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        syncCallbacks(context.coordinator)
        // 같은 파일이면 재로딩하지 않는다(스크롤 위치 보존).
        if context.coordinator.lastURL != fileURL {
            load(webView, context: context)
        }
        context.coordinator.runFindIfNeeded(findRequest, in: webView)
    }

    private func syncCallbacks(_ coordinator: Coordinator) {
        coordinator.onFindResult = onFindResult
        coordinator.scrollRatio = scrollRatio
        coordinator.onScroll = onScroll
        coordinator.fragment = fragment
        coordinator.onFragment = onFragment
    }

    private func load(_ webView: WKWebView, context: Context) {
        syncCallbacks(context.coordinator)
        context.coordinator.lastURL = fileURL
        // 새 문서가 다 뜰 때까지는 스크롤을 어느 문서 것으로도 기록하지 않는다
        // (이전 문서의 늦은 보고가 새 문서 위치를 덮지 않게).
        context.coordinator.loadedURL = nil
        // 문서 폴더까지만 읽기를 허용해 상대 경로 자산이 로드되게 한다.
        let dir = fileURL.deletingLastPathComponent()
        context.coordinator.localResourceHandler.allowedRoot = dir
        guard var url = MarkdownLocalResource.url(for: fileURL) else {
            webView.loadFileURL(fileURL, allowingReadAccessTo: dir)
            return
        }
        if let fragment = fragment(fileURL),
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.fragment = fragment
            url = components.url ?? url
        }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let bridgeName = "htmlBridge"
        /// 스크롤이 멈추면 읽던 위치(0~1)를 Swift로 보낸다.
        static let scrollReporterJS = """
        (function () {
          var timer = null;
          window.addEventListener("scroll", function () {
            if (timer) return;
            timer = setTimeout(function () {
              timer = null;
              var max = document.documentElement.scrollHeight - window.innerHeight;
              try {
                window.webkit.messageHandlers.\(bridgeName).postMessage(
                  { scroll: max > 0 ? window.pageYOffset / max : 0 });
              } catch (e) {}
            }, 150);
          }, { passive: true });
        })();
        """

        /// 문서와 문서 폴더의 자산을 웹뷰에 넘겨주는 스킴 핸들러.
        /// 웹뷰 설정이 붙들고 있으므로 코디네이터와 수명을 같이 한다.
        let localResourceHandler = MarkdownLocalResourceHandler()
        var lastURL: URL?
        var onFindResult: ((Bool) -> Void)?
        var scrollRatio: (URL) -> Double = { _ in 0 }
        var onScroll: ((Double, URL) -> Void)?
        /// 다 뜬 문서. 스크롤 보고를 이 문서 것으로 기록한다.
        var loadedURL: URL?
        var fragment: (URL) -> String? = { _ in nil }
        var onFragment: ((String?, URL) -> Void)?
        private var urlObservation: NSKeyValueObservation?
        private var lastFindRequest: FindRequest?

        /// 새 검색 요청이면 웹뷰 검색을 실행한다(마크다운 뷰어와 같은 방식).
        func runFindIfNeeded(_ request: FindRequest?, in webView: WKWebView) {
            guard let request, request != lastFindRequest else { return }
            lastFindRequest = request
            guard !request.query.isEmpty else { return }

            let config = WKFindConfiguration()
            config.backwards = !request.forward
            config.caseSensitive = false
            config.wraps = true
            webView.find(request.query, configuration: config) { [weak self] result in
                self?.onFindResult?(result.matchFound)
            }
        }

        func observeURL(of webView: WKWebView) {
            urlObservation = webView.observe(\.url) { [weak self] webView, _ in
                self?.reportFragment(of: webView)
            }
        }

        /// 다 뜬 문서의 주소 해시를 그 문서 것으로 기록한다.
        private func reportFragment(of webView: WKWebView) {
            guard let url = loadedURL else { return }
            onFragment?(webView.url?.fragment, url)
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let url = loadedURL,
                  let body = message.body as? [String: Any],
                  let ratio = body["scroll"] as? Double else { return }
            onScroll?(ratio, url)
        }

        /// 문서가 다 뜨면 기억해 둔 위치로 옮긴다.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = lastURL else { return }
            loadedURL = url
            reportFragment(of: webView)
            let ratio = scrollRatio(url)
            guard ratio > 0, ratio.isFinite else { return }
            webView.evaluateJavaScript("""
                (function () {
                  var max = document.documentElement.scrollHeight - window.innerHeight;
                  if (max > 0) window.scrollTo(0, \(ratio) * max);
                })();
                """)
        }

        /// 문서 안의 링크 클릭은 기본 브라우저에서 열어, 뷰어가 임의 사이트로
        /// 이동해 갇히지 않게 한다. 최초 파일 로드(other)만 뷰 안에서 허용한다.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                // 상대 링크는 mdlocal:// 로 들어오므로 시스템에 넘기기 전에 file://로 되돌린다.
                NSWorkspace.shared.open(MarkdownLocalResource.fileURL(for: url) ?? url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
