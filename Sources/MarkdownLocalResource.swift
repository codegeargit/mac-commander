import Foundation
import UniformTypeIdentifiers
import WebKit

/// 문서 폴더의 로컬 파일(이미지 등)을 마크다운 웹뷰로 실어 나르는 전용 URL 스킴.
///
/// `loadHTMLString(_:baseURL:)`에 `file://` 폴더를 baseURL로 넘겨도 WKWebView는
/// 그 페이지에서 로컬 파일을 하위 리소스로 읽지 못한다. 상대 경로 자체는
/// `file://...` 로 옳게 이어 붙지만 요청이 웹뷰 안에서 막혀,
/// `![](./images/a.png)` 같은 이미지가 깨진 아이콘만 남긴다.
/// 링크 클릭은 앱이 URL만 보고 직접 여는 구조라 멀쩡했고 이미지만 조용히 실패했다.
/// (`loadFileURL(_:allowingReadAccessTo:)`는 로컬 접근을 허용하지만 HTML을 파일로
/// 떨어뜨려야 해서, 문서 폴더에 임시 파일을 만들지 않고는 쓸 수 없다.)
///
/// 그래서 문서 폴더를 이 스킴의 URL로 바꿔 baseURL로 준다. 상대 경로는 웹뷰가
/// 같은 스킴으로 이어 붙이고, 요청이 오면 핸들러가 파일에서 직접 읽어 돌려준다.
///
/// HTML 뷰어(`HTMLWebView`)도 같은 스킴으로 문서를 로드한다. `loadFileURL`은
/// 응답 인코딩을 지정할 수 없어 `<meta charset>` 없는 UTF-8 HTML의 한글이 깨진다.
enum MarkdownLocalResource {
    /// 로컬 파일 전용 스킴. WKWebView는 file·http 같은 표준 스킴을 가로채지 못하므로
    /// 반드시 앱 고유 스킴이어야 한다.
    static let scheme = "mdlocal"
    /// 호스트는 쓰지 않지만, 없으면 경로 첫 컴포넌트가 호스트로 먹혀 버린다.
    private static let host = "document"
    /// 절대 경로 앞에 그대로 붙이면 되는 접두사(HTML 안 JS에서 쓴다).
    static let urlPrefix = "\(scheme)://\(host)"

    /// 파일·폴더 URL → 웹뷰가 요청할 수 있는 스킴 URL.
    /// 한글 폴더명이나 공백은 URLComponents가 퍼센트 인코딩한다.
    static func url(for fileURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        // 폴더를 baseURL로 쓰려면 끝에 슬래시가 있어야 한다. 없으면 웹뷰가
        // 마지막 컴포넌트를 파일명으로 보고 잘라내 상대 경로가 한 단계 위에서 풀린다.
        let path = fileURL.path
        components.path = fileURL.hasDirectoryPath && !path.hasSuffix("/") ? path + "/" : path
        return components.url
    }

    /// 스킴 URL → 원래의 파일 URL. 이 스킴이 아니면 nil.
    static func fileURL(for url: URL) -> URL? {
        guard url.scheme == scheme else { return nil }
        // .path는 퍼센트 디코딩된 경로를 준다(한글 폴더명도 원래 이름으로 돌아온다).
        let path = url.path
        guard !path.isEmpty, path != "/" else { return nil }
        // 상대 경로의 `..`가 그대로 실려 오므로 여기서 정리한다.
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}

/// `mdlocal://` 요청을 파일 읽기로 처리하는 핸들러.
///
/// 이미지 몇 장을 읽는 정도라 동기로 처리한다. 비동기로 돌리면 응답 도중
/// 문서가 다시 로드될 때 이미 끝난 task에 응답을 보내 크래시할 수 있다.
final class MarkdownLocalResourceHandler: NSObject, WKURLSchemeHandler {
    /// 읽기를 허용할 폴더. nil이면 제한하지 않는다.
    /// HTML 뷰어는 문서의 JS가 그대로 실행되므로, 같은 출처로 임의 경로를 fetch해
    /// 밖으로 보내지 못하게 문서 폴더로 묶는다(`loadFileURL`의 읽기 범위와 같다).
    var allowedRoot: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        guard let fileURL = MarkdownLocalResource.fileURL(for: url),
              isAllowed(fileURL),
              let data = try? Data(contentsOf: fileURL) else {
            // 경로가 틀렸거나 읽을 수 없는 경우. 웹뷰는 깨진 이미지로 표시한다.
            NSLog("[MarkdownWebView] missing resource: \(url.path)")
            urlSchemeTask.didFailWithError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }
        let mimeType = Self.mimeType(for: fileURL)
        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: Self.textEncodingName(for: data, mimeType: mimeType))
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func isAllowed(_ fileURL: URL) -> Bool {
        guard let allowedRoot else { return true }
        let root = allowedRoot.resolvingSymlinksInPath().path
        let path = fileURL.resolvingSymlinksInPath().path
        return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// 확장자로 MIME 타입을 정한다. 못 알아보면 웹뷰가 내용을 보고 판단하도록 둔다.
    private static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
    }

    /// 텍스트 파일이 UTF-8로 온전히 읽히면 응답에 UTF-8을 명시한다.
    ///
    /// 명시하지 않으면 WebKit은 `<meta charset>`이 없는 HTML·CSS·JS를 시스템 로캘의
    /// 기본 인코딩(한국어 macOS는 EUC-KR)으로 풀어 한글이 깨진다.
    /// 전송 계층 인코딩은 meta 선언보다 우선하지만, 바이트가 UTF-8로 온전히 읽힌다면
    /// UTF-8이 맞는 해석이다. UTF-8이 아닌 옛 문서(EUC-KR 등)는 nil로 두어
    /// 문서 자체 선언이나 BOM을 따르게 한다.
    private static func textEncodingName(for data: Data, mimeType: String) -> String? {
        let textTypes: Set = ["application/javascript", "application/json",
                              "application/xml", "application/xhtml+xml", "image/svg+xml"]
        guard mimeType.hasPrefix("text/") || textTypes.contains(mimeType) else { return nil }
        return String(data: data, encoding: .utf8) != nil ? "utf-8" : nil
    }
}
