import AppKit
import PDFKit
import WebKit

/// "터미널로 보내기"(⌥⌘↩): 읽던 것을 터미널 입력줄로 넘겨 AI 도구에 바로 이어 묻게 한다.
///
/// - 트리에 포커스가 있으면 고른 항목(다중 선택이면 전부)의 경로를 넣는다.
/// - 뷰어에 포커스가 있으면 선택한 글을 출처(`경로:줄`)와 함께 인용으로 넣는다.
///   선택한 글이 없으면 그 문서의 경로만 넣는다.
///
/// Enter는 누르지 않는다. 사용자가 "이 부분을 고쳐 줘"처럼 지시를 이어 쓰게 하려는 것이다.
/// 경로는 절대 경로다. 터미널에서 cd 하면 상대 경로가 어긋나고, Claude Code는 절대 경로도 그대로 읽는다.
extension WorkspaceStore {
    func sendToTerminal() {
        if case .panel(let index) = focus, let url = panels[safe: index]?.fileURL {
            let source = panels[index].content
            ViewerSelection.read { [weak self] selection in
                self?.insertSelection(selection, from: url, source: source)
            }
            return
        }
        let urls = activePane.actionTargetURLs
        guard !urls.isEmpty else { return }
        insertIntoTerminal(urls.map { Self.shellQuoted($0.path) }.joined(separator: " ") + " ")
    }

    /// 트리 우클릭 메뉴용: 그 항목이 다중 선택에 들어 있으면 선택 전체, 아니면 그 항목만 보낸다.
    func sendPathsToTerminal(for node: FileNode, in pane: TreePane) {
        let urls = pane.markedURLs.contains(node.url) ? pane.actionTargetURLs : [node.url]
        insertIntoTerminal(urls.map { Self.shellQuoted($0.path) }.joined(separator: " ") + " ")
    }

    /// 마크다운 뷰어의 보내기 버튼·우클릭 메뉴용: 그 패널에서 고른 글(비었으면 문서 경로)을 보낸다.
    func sendSelectionToTerminal(_ text: String, panel index: Int) {
        guard let url = panels[safe: index]?.fileURL else { return }
        insertSelection(text.isEmpty ? nil : ViewerSelection(text: text),
                        from: url, source: panels[index].content)
    }

    private func insertSelection(_ selection: ViewerSelection?, from url: URL, source: String?) {
        if let selection, !selection.text.isEmpty {
            insertIntoTerminal(Self.quote(selection, from: url, source: source))
        } else {
            insertIntoTerminal(Self.shellQuoted(url.path) + " ")
        }
    }

    private func insertIntoTerminal(_ text: String) {
        if showTerminal, let sink = terminalInsertSink {
            sink(text)
        } else {
            pendingTerminalInsert = text
            showTerminal = true
        }
    }

    /// 선택한 글을 `경로:시작-끝` 머리줄 + 인용(`> `) 형식으로 만든다.
    ///
    /// 줄 번호는 편집기·평문처럼 원문을 그대로 보여 주는 뷰면 정확히 안다. 렌더된 마크다운은
    /// 화면 글과 원문이 달라(`**`·`#` 등) 선택한 첫 줄과 끝 줄을 원문에서 찾아 짐작하고,
    /// 못 찾으면 줄 번호 없이 경로만 붙인다.
    static func quote(_ selection: ViewerSelection, from url: URL, source: String?) -> String {
        var header = url.path
        if let lines = selection.lines ?? source.flatMap({ guessLines(of: selection.text, in: $0) }) {
            header += lines.lowerBound == lines.upperBound
                ? ":\(lines.lowerBound)" : ":\(lines.lowerBound)-\(lines.upperBound)"
        }
        let body = selection.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.isEmpty ? ">" : "> " + $0 }
            .joined(separator: "\n")
        return header + "\n" + body + "\n"
    }

    /// 렌더된 글의 첫 줄·끝 줄이 원문 몇 번째 줄에 있는지 찾는다(1부터). 못 찾으면 nil.
    static func guessLines(of text: String, in source: String) -> ClosedRange<Int>? {
        let picked = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = picked.first, let last = picked.last else { return nil }
        // 원문 줄에서 서식 기호(`**`·`#`·목록 표시·링크 괄호)를 지워 화면 글과 맞춰 본다.
        let plainLines = source.components(separatedBy: .newlines).map { line -> String in
            var plain = line.trimmingCharacters(in: .whitespaces)
            if let marker = plain.range(of: #"^([-*+]|\d+[.)]|#{1,6}|>)\s+(\[[ xX]\]\s+)?"#,
                                        options: .regularExpression) {
                plain.removeSubrange(marker)
            }
            plain.removeAll { "*_`~[]".contains($0) }
            return plain.replacingOccurrences(of: #"\]?\([^)]*\)"#, with: "", options: .regularExpression)
        }
        // 렌더된 문단은 원문의 여러 줄이 한 줄로 이어진 것이라, 앞부분이 맞는지로 판단한다.
        func lineIndex(containing fragment: String, from start: Int) -> Int? {
            let probe = String(fragment.prefix(16))
            return plainLines.indices.dropFirst(start).first { index in
                let plain = plainLines[index]
                // 짧은 조각(짧은 제목 등)은 우연히 겹치기 쉬워 줄 전체가 같을 때만 인정한다.
                if probe.count < 4 { return plain == fragment }
                return plain.contains(probe) || (plain.count >= 6 && fragment.hasPrefix(plain.prefix(16)))
            }
        }
        guard let start = lineIndex(containing: first, from: 0) else { return nil }
        let end = lineIndex(containing: last, from: start) ?? start
        return (start + 1)...(end + 1)
    }

    /// 셸에서 그대로 쓸 수 있게 경로를 감싼다. 안전한 글자만 있으면 그대로 둔다.
    static func shellQuoted(_ path: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+,:@%~"))
        if path.unicodeScalars.allSatisfy({ safe.contains($0) }) { return path }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// 뷰어에서 선택한 글. 원문 줄 번호를 알면 함께 담는다.
struct ViewerSelection {
    var text: String
    var lines: ClosedRange<Int>?

    /// 지금 키 입력을 받는 뷰어의 선택 글을 읽는다. 웹뷰는 JS로 물어야 해서 콜백으로 돌려준다.
    @MainActor static func read(_ completion: @escaping (ViewerSelection?) -> Void) {
        guard let responder = NSApp.keyWindow?.firstResponder as? NSView else {
            completion(nil)
            return
        }
        // 편집기·평문 뷰: 원문 그대로라 줄 번호도 정확하다.
        if let textView = responder as? NSTextView, textView.isFieldEditor == false {
            let range = textView.selectedRange()
            guard range.length > 0 else { completion(nil); return }
            let all = textView.string as NSString
            let text = all.substring(with: range)
            let startLine = all.substring(to: range.location).components(separatedBy: "\n").count
            let endLine = startLine + text.trimmingCharacters(in: .newlines)
                .components(separatedBy: "\n").count - 1
            completion(ViewerSelection(text: text, lines: startLine...endLine))
            return
        }
        // PDF: 쪽 단위 문서라 줄 번호는 붙이지 않는다.
        if let pdfView = responder.enclosing(PDFView.self) {
            completion(pdfView.currentSelection?.string.map { ViewerSelection(text: $0) })
            return
        }
        // 마크다운·HTML: 웹뷰 안쪽 뷰가 first responder일 수 있어 감싼 WKWebView를 찾는다.
        if let webView = responder.enclosing(WKWebView.self) {
            webView.evaluateJavaScript("window.getSelection().toString()") { result, _ in
                let text = (result as? String) ?? ""
                completion(text.isEmpty ? nil : ViewerSelection(text: text))
            }
            return
        }
        completion(nil)
    }
}

private extension NSView {
    /// 자신 또는 상위 뷰 중에서 주어진 타입의 첫 뷰.
    func enclosing<T: NSView>(_ type: T.Type) -> T? {
        var view: NSView? = self
        while let current = view {
            if let hit = current as? T { return hit }
            view = current.superview
        }
        return nil
    }
}
