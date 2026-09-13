import SwiftUI
import WebKit

/// 마크다운 코드 블록 중 ```mermaid``` 를 실제 다이어그램으로 렌더링하는 뷰.
///
/// MarkdownUI는 mermaid를 알지 못해 코드 블록(텍스트)으로만 보여준다.
/// 여기서는 번들에 포함한 mermaid.min.js를 WKWebView로 로드해 SVG로 그린다.
/// 오프라인에서도 동작하도록 CDN이 아닌 로컬 리소스를 쓴다.
struct MermaidView: View {
    /// ```mermaid``` 블록 안의 원본 다이어그램 정의.
    let source: String
    /// 본문 폰트 크기(다이어그램 글자 크기를 뷰어와 맞추기 위해).
    let fontSize: CGFloat
    /// 다크 계열 테마 여부(mermaid 내장 다크/기본 테마 선택).
    let isDark: Bool

    /// 렌더 후 측정한 콘텐츠 높이. 처음엔 임시 높이로 두고 콜백으로 갱신한다.
    @State private var height: CGFloat = 80
    /// 렌더 실패 시 메시지(문법 오류 등). 있으면 원본 코드를 대신 보여준다.
    @State private var renderError: String?

    var body: some View {
        Group {
            if let renderError {
                // 렌더 실패: 원본 정의를 코드로 보여주고 오류를 알린다(무한 로딩 방지).
                VStack(alignment: .leading, spacing: 6) {
                    Label(renderError, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                    Text(source)
                        .font(.system(size: fontSize * 0.9, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Palette.codeBlockBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                MermaidWebView(
                    source: source,
                    fontSize: fontSize,
                    isDark: isDark,
                    onHeight: { height = $0 },
                    onError: { renderError = $0 }
                )
                .frame(height: height)
            }
        }
    }
}

/// 마우스 휠 이벤트를 자신이 소비하지 않고 바깥 스크롤뷰로 넘기는 WKWebView.
///
/// 기본 WKWebView는 커서가 위에 있으면 휠 이벤트를 삼켜, 다이어그램 위에서는
/// 문서(바깥 SwiftUI ScrollView) 스크롤이 멈춘다. 다이어그램은 뷰 높이에 맞춰
/// 전부 보이므로 내부 스크롤이 필요 없다 — 상위 계층의 NSScrollView를 찾아
/// 휠 이벤트를 그대로 넘겨 문서가 계속 스크롤되게 한다.
private final class PassthroughWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // 슈퍼뷰 체인을 거슬러 올라가 바깥 문서의 NSScrollView를 찾는다.
        var view = superview
        while let current = view {
            if let scrollView = current as? NSScrollView {
                scrollView.scrollWheel(with: event)
                return
            }
            view = current.superview
        }
        // 스크롤뷰를 못 찾으면 기본 동작(자체 처리)으로 둔다.
        super.scrollWheel(with: event)
    }
}

/// mermaid.js를 로드해 다이어그램을 그리는 WKWebView 래퍼(AppKit 브릿지).
private struct MermaidWebView: NSViewRepresentable {
    let source: String
    let fontSize: CGFloat
    let isDark: Bool
    let onHeight: (CGFloat) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeight: onHeight, onError: onError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        // JS → Swift 브릿지: 렌더 완료 높이와 오류를 전달받는다.
        controller.add(context.coordinator, name: "mermaidBridge")
        config.userContentController = controller

        // 휠 이벤트를 삼키지 않고 부모 스크롤뷰로 넘기는 서브클래스를 쓴다.
        let webView = PassthroughWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // 배경을 투명하게 두어 뷰어 배경색이 그대로 비치게 한다.
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(context.coordinator.html(source: source, fontSize: fontSize, isDark: isDark),
                               baseURL: MermaidAsset.baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // 소스/폰트/테마가 바뀌면 다시 로드한다. 같은 값이면 재로딩을 건너뛴다.
        let key = context.coordinator.key(source: source, fontSize: fontSize, isDark: isDark)
        guard key != context.coordinator.lastKey else { return }
        context.coordinator.lastKey = key
        webView.loadHTMLString(context.coordinator.html(source: source, fontSize: fontSize, isDark: isDark),
                               baseURL: MermaidAsset.baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onHeight: (CGFloat) -> Void
        let onError: (String) -> Void
        var lastKey: String = ""

        init(onHeight: @escaping (CGFloat) -> Void, onError: @escaping (String) -> Void) {
            self.onHeight = onHeight
            self.onError = onError
        }

        func key(source: String, fontSize: CGFloat, isDark: Bool) -> String {
            "\(isDark)-\(Int(fontSize))-\(source.hashValue)"
        }

        /// JS에서 보낸 렌더 결과({height} 또는 {error}) 처리.
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            if let error = body["error"] as? String {
                DispatchQueue.main.async { self.onError(error) }
            } else if let height = body["height"] as? Double {
                // 여백을 조금 더해 잘림 방지. 최소 높이 보장.
                DispatchQueue.main.async { self.onHeight(max(40, CGFloat(height) + 8)) }
            }
        }

        /// mermaid 정의 + JS를 담은 HTML 문서를 만든다.
        func html(source: String, fontSize: CGFloat, isDark: Bool) -> String {
            let theme = isDark ? "dark" : "default"
            // 다이어그램 정의를 JS 문자열 리터럴로 안전하게 삽입.
            let escaped = source
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            let script = MermaidAsset.scriptTag
            return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
              html, body { margin: 0; padding: 0; background: transparent; }
              body { font-size: \(Int(fontSize))px; overflow: hidden; }
              #d { display: flex; justify-content: center; }
              #d svg { max-width: 100%; height: auto; }
            </style>
            </head>
            <body>
            <div id="d"></div>
            \(script)
            <script>
              function report(payload) {
                try { window.webkit.messageHandlers.mermaidBridge.postMessage(payload); } catch (e) {}
              }
              (async function () {
                try {
                  mermaid.initialize({ startOnLoad: false, theme: "\(theme)",
                    securityLevel: "strict", fontSize: \(Int(fontSize)) });
                  const def = `\(escaped)`;
                  const { svg } = await mermaid.render("g", def);
                  document.getElementById("d").innerHTML = svg;
                  // 레이아웃이 끝난 다음 프레임에 실제 높이를 측정해 보고한다.
                  requestAnimationFrame(function () {
                    const h = document.getElementById("d").getBoundingClientRect().height;
                    report({ height: h });
                  });
                } catch (e) {
                  report({ error: String(e && e.message ? e.message : e) });
                }
              })();
            </script>
            </body>
            </html>
            """
        }
    }
}

/// 번들에 포함된 mermaid.min.js를 찾아 HTML에 인라인으로 삽입하기 위한 헬퍼.
enum MermaidAsset {
    /// 리소스 폴더를 baseURL로 써서 WebView가 로컬 파일 컨텍스트에서 실행되게 한다.
    static let baseURL: URL? = url?.deletingLastPathComponent()

    /// 번들 내 mermaid.min.js 경로.
    static let url: URL? = Bundle.main.url(forResource: "mermaid.min", withExtension: "js")

    /// mermaid.js 내용을 <script>로 감싼 문자열(없으면 CDN 폴백).
    static let scriptTag: String = {
        if let url, let js = try? String(contentsOf: url, encoding: .utf8) {
            return "<script>\n\(js)\n</script>"
        }
        // 번들에서 못 찾으면 CDN 폴백(네트워크 필요).
        return #"<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>"#
    }()

    /// 이 코드 블록을 mermaid로 렌더링해야 하는지 언어 태그로 판별.
    static func isMermaid(language: String?) -> Bool {
        language?.lowercased() == "mermaid"
    }
}
