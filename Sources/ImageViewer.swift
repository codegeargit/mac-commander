import SwiftUI
import AppKit

/// 이미지 파일을 표시하는 뷰어.
/// zoom == 0이면 "맞춤"(패널 크기에 가로·세로 모두 맞춰 확대/축소), zoom > 0이면 명시적 배율.
/// 이미지는 항상 뷰 가운데에 정렬되며, 뷰보다 크면 스크롤/드래그로 이동한다.
/// Cmd+휠 또는 트랙패드 두 손가락 핀치로 확대/축소한다.
struct ImageViewer: NSViewRepresentable {
    let url: URL
    /// 확대 배율. 0이면 맞춤 모드.
    var zoom: CGFloat = 0
    /// 배율이 바뀔 때 호출(스토어 반영용). Cmd+휠 확대 및 맞춤 상태의 실제 배율 보고.
    var onZoom: ((CGFloat) -> Void)?
    /// 맞춤 모드에서 실제 적용 배율(%)을 상위에 알린다(헤더 % 표시용).
    var onFitScale: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> ImageCanvasView {
        let view = ImageCanvasView()
        view.onZoomChange = onZoom
        view.onFitScaleChange = onFitScale
        view.load(url: url)
        view.apply(zoom: zoom)
        return view
    }

    func updateNSView(_ view: ImageCanvasView, context: Context) {
        view.onZoomChange = onZoom
        view.onFitScaleChange = onFitScale
        if view.loadedURL != url {
            view.load(url: url)
        }
        view.apply(zoom: zoom)
    }

}

/// 이미지를 담아 항상 가운데 정렬하고, 맞춤/명시 배율을 계산해 그리는 뷰.
/// 자체적으로 스크롤(clip) 없이, 확대 상태에서는 드래그(pan)로 이동한다.
final class ImageCanvasView: NSView {
    private(set) var loadedURL: URL?
    /// Cmd+휠로 배율이 바뀌면 새 배율을 상위에 알린다.
    var onZoomChange: ((CGFloat) -> Void)?
    /// 맞춤 모드의 실제 적용 배율을 상위에 알린다(헤더 % 표시).
    var onFitScaleChange: ((CGFloat) -> Void)?

    private var image: NSImage?
    /// 원본 픽셀 크기(포인트가 아닌 실제 픽셀 기준으로 배율을 계산).
    private var pixelSize: NSSize = .zero
    /// 현재 배율(0이면 맞춤). >0이면 pixelSize × zoom이 표시 크기.
    private var currentZoom: CGFloat = 0
    /// 마지막으로 상위에 보고한 맞춤 배율(중복 보고 방지).
    private var lastReportedFit: CGFloat = -1
    /// 확대 상태에서 사용자가 드래그해 이동한 콘텐츠 오프셋(가운데 기준 상대값).
    private var panOffset: NSPoint = .zero
    private var lastDragPoint: NSPoint?
    /// 핀치 제스처가 시작될 때의 배율. 제스처의 magnification은 시작 이후 누적값이라
    /// 매번 이 기준에 곱해야 손가락을 벌린 만큼만 커진다.
    private var magnifyBaseZoom: CGFloat = 0
    /// 핀치가 진행 중인지. 진행 중에는 보간 품질을 낮춰 매 프레임 리샘플링 비용을 줄인다
    /// (큰 사진은 고품질 보간으로 매번 다시 그리면 확대가 눈에 띄게 끊긴다).
    private var isInteractiveZoom = false

    private static let minZoom: CGFloat = 0.05
    private static let maxZoom: CGFloat = 16.0

    private var scrollMonitor: Any?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true   // macOS 14+ 기본값 false — 프레임 밖 그리기 방지
        translatesAutoresizingMaskIntoConstraints = true
        installMagnificationGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = true
        installMagnificationGesture()
    }

    /// 이미지 뷰는 자체 콘텐츠 크기를 요구하지 않는다(부모가 준 크기에 맞춘다).
    /// 이를 명시하지 않으면 큰 이미지가 오토레이아웃에서 최소 폭을 주장해
    /// SwiftUI HStack의 고정폭 사이드바(좌측 트리)를 밀어낼 수 있다.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    /// 이미지를 로드한다. 실패하면 빈 상태로 둔다.
    func load(url: URL) {
        loadedURL = url
        let img = NSImage(contentsOf: url)
        image = img
        pixelSize = img.map { Self.pixelDimensions(of: $0) } ?? .zero
        panOffset = .zero
        lastReportedFit = -1   // 새 이미지는 맞춤 배율을 반드시 다시 보고
        needsDisplay = true
        reportFitScale()
    }

    /// NSImage의 실제 픽셀 크기(레티나/DPI 무관하게 비트맵 픽셀 기준).
    private static func pixelDimensions(of image: NSImage) -> NSSize {
        for rep in image.representations {
            if rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
                return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            }
        }
        return image.size
    }

    /// 배율을 적용한다. zoom==0이면 맞춤, >0이면 명시 배율.
    /// 배율이 바뀌면 팬 오프셋을 초기화해(가운데로) 위치가 튀지 않게 한다.
    func apply(zoom: CGFloat) {
        guard currentZoom != zoom else { return }
        currentZoom = zoom
        panOffset = .zero
        needsDisplay = true
        reportFitScale()
    }

    /// 현재 맞춤 배율(뷰 크기 기준). 명시 배율일 땐 그 값 그대로.
    private func effectiveScale() -> CGFloat {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return 1 }
        if currentZoom > 0 { return currentZoom }
        return fitScale()
    }

    /// 맞춤 배율: 뷰의 가로·세로 중 더 빡빡한 쪽에 맞춘다(작으면 확대, 크면 축소).
    private func fitScale() -> CGFloat {
        guard pixelSize.width > 0, pixelSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(bounds.width / pixelSize.width, bounds.height / pixelSize.height)
    }

    /// 맞춤 모드일 때 현재 적용 배율을 상위에 알린다(헤더 % 표시용).
    ///
    /// 중요: 이 콜백은 상위 SwiftUI의 @Published 상태를 바꾼다. 레이아웃/그리기
    /// 패스 도중에 동기로 호출하면 "뷰 업데이트 중 상태 변경"이 되어 레이아웃이
    /// 재귀적으로 다시 돌며 전체 UI(좌측 트리 포함)가 불안정해진다.
    /// 그래서 값이 실제로 바뀔 때만, 다음 런루프로 비동기 디스패치해 보고한다.
    private func reportFitScale() {
        guard currentZoom == 0 else { return }
        let fit = fitScale()
        guard abs(fit - lastReportedFit) > 0.0001 else { return }
        lastReportedFit = fit
        DispatchQueue.main.async { [weak self] in
            self?.onFitScaleChange?(fit)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // 뷰 크기가 바뀌면 맞춤 배율이 달라지므로 다시 그리고 % 갱신.
        needsDisplay = true
        reportFitScale()
    }

    override func draw(_ dirtyRect: NSRect) {
        // 배경은 반드시 bounds로만 칠한다. macOS 14부터 NSView.clipsToBounds 기본값이
        // false라 AppKit이 bounds보다 큰 dirtyRect(윈도우 전체까지)를 넘길 수 있는데,
        // 그걸 그대로 채우면 이 뷰 프레임 밖(좌측 트리·패널 헤더)까지 배경색이 덮인다.
        NSColor(Palette.viewerBackground).setFill()
        bounds.fill()

        guard let image, pixelSize.width > 0, pixelSize.height > 0 else { return }

        // 확대 시 이미지가 패널 밖(트리·헤더 위)으로 새어 나가지 않도록 자른다.
        NSGraphicsContext.current?.saveGraphicsState()
        defer { NSGraphicsContext.current?.restoreGraphicsState() }
        NSBezierPath(rect: bounds).setClip()

        let scale = effectiveScale()
        let drawW = pixelSize.width * scale
        let drawH = pixelSize.height * scale

        // 기본은 뷰 가운데. 확대되어 뷰보다 크면 드래그 오프셋을 반영해 이동.
        var x = (bounds.width - drawW) / 2
        var y = (bounds.height - drawH) / 2

        if drawW > bounds.width {
            x = clamp((bounds.width - drawW) / 2 + panOffset.x,
                      min: bounds.width - drawW, max: 0)
        }
        if drawH > bounds.height {
            y = clamp((bounds.height - drawH) / 2 + panOffset.y,
                      min: bounds.height - drawH, max: 0)
        }

        let rect = NSRect(x: x, y: y, width: drawW, height: drawH)
        // 핀치 도중에는 낮은 보간으로 빠르게, 손을 떼면 고품질로 한 번 더 그린다.
        let quality: NSImageInterpolation = isInteractiveZoom ? .low : .high
        NSGraphicsContext.current?.imageInterpolation = quality
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0,
                   respectFlipped: true, hints: [.interpolation: quality.rawValue])
    }

    private func clamp(_ v: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.max(lo, Swift.min(hi, v))
    }

    // MARK: - 드래그(pan) 이동 — 확대되어 뷰보다 큰 경우만

    /// 확대되어 스크롤 여지가 있을 때만 손 커서를 표시.
    override func resetCursorRects() {
        if isPannable() { addCursorRect(bounds, cursor: .openHand) }
    }

    private func isPannable() -> Bool {
        let scale = effectiveScale()
        return pixelSize.width * scale > bounds.width + 1 ||
               pixelSize.height * scale > bounds.height + 1
    }

    override func mouseDown(with event: NSEvent) {
        if isPannable() {
            lastDragPoint = convert(event.locationInWindow, from: nil)
            NSCursor.closedHand.set()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastDragPoint else { super.mouseDragged(with: event); return }
        let now = convert(event.locationInWindow, from: nil)
        // isFlipped(true)라 y가 아래로 증가. 드래그 방향대로 콘텐츠 이동.
        panOffset.x += now.x - last.x
        panOffset.y += now.y - last.y
        lastDragPoint = now
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if lastDragPoint != nil {
            lastDragPoint = nil
            NSCursor.openHand.set()
        } else {
            super.mouseUp(with: event)
        }
    }

    // MARK: - 트랙패드 핀치 확대/축소

    /// 두 손가락 핀치를 받는다. 휠 이벤트와 달리 제스처는 이 뷰(와 그 안쪽)에서
    /// 일어난 것만 오므로 커서 위치를 따로 확인할 필요가 없다.
    private func installMagnificationGesture() {
        addGestureRecognizer(
            NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:))))
    }

    /// 핀치가 진행되는 동안에는 배율을 이 뷰 안에서만 바꾸고 스토어에는 알리지 않는다.
    /// 알리면 @Published 변경이 매 이벤트마다 SwiftUI 전체(트리 포함)를 다시 그리게 해
    /// 손을 뗀 뒤에도 확대가 따라오는 것처럼 느려진다. 손을 뗄 때 한 번만 반영한다.
    @objc private func handleMagnify(_ recognizer: NSMagnificationGestureRecognizer) {
        switch recognizer.state {
        case .began:
            // 맞춤 상태면 지금 화면에 보이는 실제 배율에서 확대를 시작한다.
            magnifyBaseZoom = currentZoom > 0 ? currentZoom : fitScale()
            isInteractiveZoom = true
        case .changed:
            guard magnifyBaseZoom > 0 else { return }
            let newScale = clamp(magnifyBaseZoom * (1 + recognizer.magnification),
                                 min: Self.minZoom, max: Self.maxZoom)
            guard abs(newScale - currentZoom) > 0.0001 else { return }
            currentZoom = newScale
            panOffset = .zero
            needsDisplay = true
        case .ended, .cancelled:
            isInteractiveZoom = false
            needsDisplay = true   // 고품질 보간으로 한 번 더 그린다
            window?.invalidateCursorRects(for: self)
            if currentZoom > 0 { onZoomChange?(currentZoom) }
        default:
            break
        }
    }

    // MARK: - Cmd+휠 확대/축소

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.contains(.command),
              let window, event.window === window else { return event }
        let pointInView = convert(event.locationInWindow, from: nil)
        guard bounds.contains(pointInView) else { return event }

        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        guard delta != 0 else { return nil }

        // 맞춤 상태면 현재 실제 배율에서 확대를 시작한다.
        let base = currentZoom > 0 ? currentZoom : fitScale()
        let factor: CGFloat = 1 + (delta > 0 ? 0.1 : -0.1)
        let newScale = clamp(base * factor, min: Self.minZoom, max: Self.maxZoom)
        currentZoom = newScale
        panOffset = .zero
        needsDisplay = true
        window.invalidateCursorRects(for: self)
        onZoomChange?(newScale)
        return nil
    }
}
