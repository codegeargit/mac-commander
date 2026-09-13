import SwiftUI
import PDFKit

/// 확대 상태에서 마우스로 잡고 끌어(hand-drag) 이동할 수 있는 PDFView.
/// PDFView 내부 스크롤뷰를 찾아 드래그 변위만큼 콘텐츠를 이동시킨다.
final class PannablePDFView: PDFView {
    private var lastDragPoint: NSPoint?

    /// Cmd+휠로 배율이 바뀌면 새 배율을 상위(스토어)에 알린다.
    var onZoomChange: ((CGFloat) -> Void)?

    /// Cmd+휠 이벤트 로컬 모니터. PDFView 내부 스크롤뷰가 scrollWheel을 먼저
    /// 가로채므로 서브클래스 override로는 못 잡는다. 로컬 모니터로 확실히 가로챈다.
    private var scrollMonitor: Any?

    private static let minZoom: CGFloat = 0.25
    private static let maxZoom: CGFloat = 6.0

    /// 핀치 제스처가 시작될 때의 배율(제스처의 magnification은 시작 이후 누적값).
    private var magnifyBaseScale: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installMagnificationGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installMagnificationGesture()
    }

    // MARK: - 트랙패드 핀치 확대/축소

    /// 두 손가락 핀치를 직접 받아 scaleFactor를 조절한다.
    /// PDFKit에 그냥 맡기면 배율이 바뀌어도 스토어에 알리지 못해 헤더의 % 표시와
    /// 어긋나고, 맞춤 모드(autoScales)에서는 다음 갱신 때 곧바로 되돌아간다.
    /// 제스처 인식기는 PDFView 내부 스크롤뷰에서 일어난 핀치까지 받는다.
    private func installMagnificationGesture() {
        addGestureRecognizer(
            NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:))))
    }

    /// 핀치 도중에는 PDFView의 배율만 바꾸고 스토어에는 알리지 않는다.
    /// 매 이벤트마다 알리면 @Published 변경이 SwiftUI 갱신을 연쇄로 일으켜
    /// 확대가 손가락을 못 따라온다. 손을 뗄 때 최종 배율을 한 번만 반영한다.
    @objc private func handleMagnify(_ recognizer: NSMagnificationGestureRecognizer) {
        switch recognizer.state {
        case .began:
            magnifyBaseScale = scaleFactor
        case .changed:
            guard magnifyBaseScale > 0 else { return }
            let newScale = min(max(magnifyBaseScale * (1 + recognizer.magnification),
                                   Self.minZoom), Self.maxZoom)
            guard abs(newScale - scaleFactor) > 0.0001 else { return }
            if autoScales { autoScales = false }
            scaleFactor = newScale
        case .ended, .cancelled:
            guard magnifyBaseScale > 0 else { return }
            onZoomChange?(scaleFactor)
        default:
            break
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 창에 붙을 때 모니터 설치, 떨어질 때 해제.
        if window != nil, scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handleScroll(event)
            }
        } else if window == nil, let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    deinit {
        if let monitor = scrollMonitor { NSEvent.removeMonitor(monitor) }
    }

    /// Cmd+휠이고 커서가 이 뷰 위에 있으면 확대/축소하고 이벤트를 삼킨다(nil 반환).
    /// 그 외에는 이벤트를 그대로 흘려 기본 스크롤이 되게 한다.
    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.contains(.command),
              let window, event.window === window else { return event }
        // 커서가 이 PDF 뷰 영역 안인지 확인.
        let pointInView = convert(event.locationInWindow, from: nil)
        guard bounds.contains(pointInView) else { return event }

        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        guard delta != 0 else { return nil }
        let factor: CGFloat = 1 + (delta > 0 ? 0.1 : -0.1)
        let newScale = min(max(scaleFactor * factor, Self.minZoom), Self.maxZoom)
        if autoScales { autoScales = false }
        scaleFactor = newScale
        onZoomChange?(newScale)
        return nil   // 이벤트 소비(기본 스크롤 방지)
    }

    /// 내부 문서 스크롤뷰(콘텐츠 이동 대상).
    private var documentScrollView: NSScrollView? {
        // PDFView는 내부에 NSScrollView를 품고 있다. 서브뷰 계층에서 찾는다.
        func find(in view: NSView) -> NSScrollView? {
            if let sv = view as? NSScrollView { return sv }
            for sub in view.subviews {
                if let sv = find(in: sub) { return sv }
            }
            return nil
        }
        return find(in: self)
    }

    /// 손 도구 커서로 "끌 수 있음"을 표시.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        // 확대되어 스크롤 여지가 있을 때만 드래그 이동을 가로챈다.
        if let clip = documentScrollView?.contentView, isScrollable(clip) {
            lastDragPoint = convert(event.locationInWindow, from: nil)
            NSCursor.closedHand.set()
        } else {
            super.mouseDown(with: event)  // 텍스트 선택 등 기본 동작 유지
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastDragPoint,
              let clip = documentScrollView?.contentView else {
            super.mouseDragged(with: event); return
        }
        let now = convert(event.locationInWindow, from: nil)
        let dx = now.x - last.x
        let dy = now.y - last.y
        lastDragPoint = now

        var origin = clip.bounds.origin
        // 뷰 좌표계는 flipped가 아닐 수 있어 y는 드래그 반대 방향으로 이동.
        origin.x -= dx
        origin.y += clip.isFlipped ? -dy : dy
        clip.scroll(to: clampedOrigin(origin, in: clip))
        documentScrollView?.reflectScrolledClipView(clip)
    }

    override func mouseUp(with event: NSEvent) {
        if lastDragPoint != nil {
            lastDragPoint = nil
            NSCursor.openHand.set()
        } else {
            super.mouseUp(with: event)
        }
    }

    /// 스크롤 여지(콘텐츠가 clip보다 큼)가 있는지.
    private func isScrollable(_ clip: NSClipView) -> Bool {
        guard let doc = clip.documentView else { return false }
        return doc.frame.width > clip.bounds.width + 1 ||
               doc.frame.height > clip.bounds.height + 1
    }

    /// 스크롤 원점이 콘텐츠 밖으로 나가지 않게 제한.
    private func clampedOrigin(_ origin: NSPoint, in clip: NSClipView) -> NSPoint {
        guard let doc = clip.documentView else { return origin }
        let maxX = max(0, doc.frame.width - clip.bounds.width)
        let maxY = max(0, doc.frame.height - clip.bounds.height)
        return NSPoint(x: min(max(origin.x, 0), maxX),
                       y: min(max(origin.y, 0), maxY))
    }
}

/// PDFKit의 PDFView를 SwiftUI로 감싼 뷰어.
/// URL이 바뀌면 문서를 다시 로드한다.
/// zoom == 0이면 폭 맞춤(autoScale), zoom > 0이면 명시적 배율.
/// Cmd+휠과 트랙패드 두 손가락 핀치로 확대/축소하고,
/// 확대 상태에서는 마우스 드래그로 이동(panning)할 수 있다.
struct PDFViewer: NSViewRepresentable {
    let url: URL
    /// 확대 배율. 0이면 폭 맞춤 모드.
    var zoom: CGFloat = 0
    /// Cmd+휠로 배율이 바뀔 때 호출(스토어 반영용).
    var onZoom: ((CGFloat) -> Void)?
    /// 문서 내 찾기 요청(⌘F 바에서 내려온다). nil이면 대기.
    var findRequest: FindRequest?
    /// 검색 결과 유무를 찾기 바에 알린다.
    var onFindResult: ((Bool) -> Void)?
    /// 현재 쪽·전체 쪽수를 알린다(헤더 표시용).
    var onPageChange: ((Int, Int) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 마지막으로 실행한 검색 요청을 기억해 같은 요청을 두 번 실행하지 않는다.
    final class Coordinator {
        var lastFindRequest: FindRequest?
        /// 쪽 변경 알림 구독 토큰.
        var pageObserver: NSObjectProtocol?
        /// 갱신된 콜백(뷰가 다시 만들어져도 최신 것을 쓰도록 여기에 보관).
        var onPageChange: ((Int, Int) -> Void)?
        /// 마지막으로 보고한 (현재 쪽, 전체 쪽). 같으면 다시 알리지 않는다.
        var lastReported: (Int, Int) = (0, 0)

        deinit {
            if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) }
        }
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PannablePDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor(Palette.viewerBackground)
        view.document = PDFDocument(url: url)
        view.onZoomChange = onZoom
        applyZoom(to: view)

        // 스크롤로 보이는 쪽이 바뀔 때마다 알림이 온다. 문서를 처음 연 직후에는
        // 알림이 오지 않으므로 아래에서 한 번 직접 보고한다.
        let coordinator = context.coordinator
        coordinator.onPageChange = onPageChange
        coordinator.pageObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged, object: view, queue: .main
        ) { [weak view] _ in
            guard let view else { return }
            Self.reportPage(view, coordinator)
        }
        Self.reportPage(view, coordinator)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        view.backgroundColor = NSColor(Palette.viewerBackground)
        (view as? PannablePDFView)?.onZoomChange = onZoom
        context.coordinator.onPageChange = onPageChange
        // 열린 문서가 다른 파일이면 교체(같은 파일 재로딩은 건너뜀).
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            // 새 문서는 쪽수가 다르다. 이전 값과 같다고 걸러지지 않게 초기화한다.
            context.coordinator.lastReported = (0, 0)
        }
        applyZoom(to: view)
        runFindIfNeeded(in: view, coordinator: context.coordinator)
        Self.reportPage(view, context.coordinator)
    }

    /// 현재 쪽·전체 쪽수를 상위에 알린다. 값이 그대로면 아무것도 하지 않는다.
    private static func reportPage(_ view: PDFView, _ coordinator: Coordinator) {
        guard let document = view.document else { return }
        let count = document.pageCount
        let current = view.currentPage.map { document.index(for: $0) + 1 } ?? 0
        guard (current, count) != coordinator.lastReported else { return }
        coordinator.lastReported = (current, count)
        // 뷰 갱신 도중에 상태를 바꾸면 SwiftUI가 경고를 낸다. 다음 루프로 미룬다.
        DispatchQueue.main.async { coordinator.onPageChange?(current, count) }
    }

    /// 새 검색 요청이면 PDF 문서에서 찾아 그 위치를 선택하고 화면에 보인다.
    private func runFindIfNeeded(in view: PDFView, coordinator: Coordinator) {
        guard let request = findRequest, request != coordinator.lastFindRequest else { return }
        coordinator.lastFindRequest = request
        guard !request.query.isEmpty, let document = view.document else { return }

        var options: NSString.CompareOptions = [.caseInsensitive]
        if !request.forward { options.insert(.backwards) }

        // 현재 선택 다음(또는 이전)부터 찾고, 문서 끝에 닿으면 처음부터 한 번 더 훑는다.
        var match = document.findString(request.query,
                                       fromSelection: view.currentSelection,
                                       withOptions: options)
        if match == nil {
            match = document.findString(request.query, fromSelection: nil, withOptions: options)
        }
        guard let match else {
            onFindResult?(false)
            return
        }
        view.setCurrentSelection(match, animate: true)
        view.scrollSelectionToVisible(nil)
        onFindResult?(true)
    }

    /// zoom 값에 따라 폭 맞춤(autoScale) 또는 명시적 배율을 적용.
    private func applyZoom(to view: PDFView) {
        if zoom > 0 {
            if view.autoScales { view.autoScales = false }
            // 불필요한 재설정을 피해 스크롤 튐 방지.
            if abs(view.scaleFactor - zoom) > 0.001 {
                view.scaleFactor = zoom
            }
        } else {
            if !view.autoScales { view.autoScales = true }
        }
    }
}
