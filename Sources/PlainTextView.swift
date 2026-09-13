import SwiftUI
import AppKit

/// 마크다운이 아닌 텍스트 파일(로그·CSV·코드 등)을 고정폭으로 보여주는 읽기 전용 뷰어.
///
/// 원래는 SwiftUI `Text` 하나로 본문 전체를 그렸는데 두 가지가 걸렸다.
/// - `Text`에는 문서 내 찾기(⌘F)를 걸 수단이 없다.
/// - 수만 줄짜리 로그를 한 `Text`로 그리면 레이아웃을 한 번에 계산해 버벅인다.
///
/// NSTextView로 옮겨 검색(`showFindIndicator`로 결과 강조)과 텍스트 선택·복사를
/// AppKit에 맡긴다. 고정폭·줄 간격·여백은 기존 표시와 같게 맞췄다.
struct PlainTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let colors: ColorSet
    /// 문서 내 찾기 요청(⌘F 바에서 내려온다). nil이면 대기.
    var findRequest: FindRequest?
    /// 검색 결과 유무를 찾기 바에 알린다.
    var onFindResult: ((Bool) -> Void)?
    /// 트랙패드 핀치로 글자 크기를 한 단계 조절해 달라는 요청(+1 확대, -1 축소).
    var onZoomStep: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        /// 이미 반영한 본문·서식. 같으면 다시 설정하지 않아 스크롤 위치가 유지된다.
        var appliedKey: String = ""
        var lastFindRequest: FindRequest?
        var onZoomStep: ((Int) -> Void)?

        /// 마지막으로 글자 크기를 한 단계 옮긴 시점의 누적 배율.
        private var lastSteppedMagnification: CGFloat = 0
        /// 한 단계(글자 1pt)를 옮기는 데 필요한 핀치 양.
        private static let stepThreshold: CGFloat = 0.12

        /// 트랙패드 두 손가락 핀치로 본문 글자 크기를 조절한다.
        /// 평문 뷰어는 배율이 아니라 폰트 크기(정수 단계)로 커지므로, 누적 배율이
        /// 한 단계를 넘을 때마다 한 칸씩 키우거나 줄인다.
        @objc func handleMagnify(_ recognizer: NSMagnificationGestureRecognizer) {
            switch recognizer.state {
            case .began:
                lastSteppedMagnification = 0
            case .changed:
                let delta = recognizer.magnification - lastSteppedMagnification
                guard abs(delta) >= Self.stepThreshold else { return }
                lastSteppedMagnification = recognizer.magnification
                onZoomStep?(delta > 0 ? 1 : -1)
            default:
                break
            }
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.addGestureRecognizer(
            NSMagnificationGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleMagnify(_:))))

        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.drawsBackground = true
            // 기존 표시와 같은 여백(가로 20 / 세로 16).
            textView.textContainerInset = NSSize(width: 20, height: 16)
            // 폭에 맞춰 줄바꿈한다(기존 Text 표시와 동일).
            textView.textContainer?.widthTracksTextView = true
        }
        context.coordinator.onZoomStep = onZoomStep
        apply(scrollView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // 콜백은 갱신마다 새로 만들어지므로 항상 최신 것으로 바꿔 둔다.
        context.coordinator.onZoomStep = onZoomStep
        apply(scrollView, context: context)
        runFindIfNeeded(scrollView, coordinator: context.coordinator)
    }

    /// 본문·폰트·테마를 반영한다. 바뀐 게 없으면 건드리지 않는다.
    private func apply(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let background = NSColor(colors.viewerBackground)
        scrollView.backgroundColor = background
        textView.backgroundColor = background

        let key = "\(Int(fontSize))-\(colors.textPrimary.hexString)-\(text.hashValue)"
        guard key != context.coordinator.appliedKey else { return }
        context.coordinator.appliedKey = key

        let style = NSMutableParagraphStyle()
        style.lineSpacing = fontSize * 0.35   // 기존 표시의 줄 간격과 같게
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor(colors.textPrimary),
            .paragraphStyle: style,
        ]
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: attributes))
        // 선택 색도 테마를 따르게 한다(기본값은 시스템 강조색).
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(colors.selectBackground),
            .foregroundColor: NSColor(colors.selectForeground),
        ]
    }

    /// 새 검색 요청이면 본문에서 찾아 선택하고 화면에 보인다.
    private func runFindIfNeeded(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let request = findRequest, request != coordinator.lastFindRequest,
              let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.lastFindRequest = request
        guard !request.query.isEmpty else { return }

        let full = textView.string as NSString
        guard full.length > 0 else {
            onFindResult?(false)
            return
        }

        var options: NSString.CompareOptions = [.caseInsensitive]
        if !request.forward { options.insert(.backwards) }

        let selected = textView.selectedRange()
        // 증분 검색은 지금 선택된 자리에서 다시 찾는다(한 글자마다 앞으로 밀리지 않게).
        // "다음/이전 찾기"는 현재 결과 바깥에서 이어 찾는다.
        let searchRange: NSRange
        if request.forward {
            let start = request.isNewSearch ? selected.location
                                            : min(selected.location + selected.length, full.length)
            searchRange = NSRange(location: start, length: full.length - start)
        } else {
            searchRange = NSRange(location: 0, length: selected.location)
        }

        var found = searchRange.length > 0
            ? full.range(of: request.query, options: options, range: searchRange)
            : NSRange(location: NSNotFound, length: 0)
        if found.location == NSNotFound {
            // 끝(또는 처음)에 닿았으면 문서 전체에서 한 번 더 훑는다.
            found = full.range(of: request.query, options: options,
                               range: NSRange(location: 0, length: full.length))
        }
        guard found.location != NSNotFound else {
            onFindResult?(false)
            return
        }
        textView.setSelectedRange(found)
        textView.scrollRangeToVisible(found)
        textView.showFindIndicator(for: found)
        onFindResult?(true)
    }
}
