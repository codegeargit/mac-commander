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

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(
            context.coordinator.localResourceHandler,
            forURLScheme: MarkdownLocalResource.scheme)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // 트랙패드 두 손가락 핀치 확대(WKWebView 기본값은 꺼져 있다).
        webView.allowsMagnification = true
        load(webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onFindResult = onFindResult
        // 같은 파일이면 재로딩하지 않는다(스크롤 위치 보존).
        if context.coordinator.lastURL != fileURL {
            load(webView, context: context)
        }
        context.coordinator.runFindIfNeeded(findRequest, in: webView)
    }

    private func load(_ webView: WKWebView, context: Context) {
        context.coordinator.lastURL = fileURL
        // 문서 폴더까지만 읽기를 허용해 상대 경로 자산이 로드되게 한다.
        let dir = fileURL.deletingLastPathComponent()
        context.coordinator.localResourceHandler.allowedRoot = dir
        guard let url = MarkdownLocalResource.url(for: fileURL) else {
            webView.loadFileURL(fileURL, allowingReadAccessTo: dir)
            return
        }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        /// 문서와 문서 폴더의 자산을 웹뷰에 넘겨주는 스킴 핸들러.
        /// 웹뷰 설정이 붙들고 있으므로 코디네이터와 수명을 같이 한다.
        let localResourceHandler = MarkdownLocalResourceHandler()
        var lastURL: URL?
        var onFindResult: ((Bool) -> Void)?
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
