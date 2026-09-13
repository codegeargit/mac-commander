import SwiftUI
import AppKit

/// 패널 사이의 폭·높이 조절 구분선(트리↔뷰어, 뷰어↔뷰어, 뷰어↔터미널 공용).
///
/// 커서 변경과 드래그를 AppKit에서 직접 처리한다. SwiftUI의
/// `.onHover { NSCursor.resizeLeftRight.push() }` 방식은 경계 한쪽에서만 커서가
/// 바뀌는 문제가 있었고, 원인이 둘이었다.
///
/// 1. 스택에서 구분선보다 **나중에 선언된 뷰**(뷰어·터미널)가 위에 그려지면서
///    구분선의 히트 영역 중 그쪽 절반을 덮는다 → hover 자체가 오지 않는다.
///    (호출 측에서 `.zIndex(1)`로 구분선을 형제 위로 올려 해결한다)
/// 2. WKWebView·SwiftTerm은 자기 영역에서 `cursorUpdate`로 커서를 되돌려 놓는다.
///    겹친 지점에서는 push한 커서가 곧바로 밀린다.
///
/// 그래서 커서를 AppKit 커서 렉트로 등록해 커서 관리 경쟁에서 이기게 하고,
/// 드래그도 같은 뷰의 마우스 이벤트로 처리해 push/pop 스택 불균형을 없앤다.
struct ResizeDivider: View {
    enum Axis {
        /// 좌우 폭을 조절하는 세로선.
        case horizontal
        /// 위아래 높이를 조절하는 가로선.
        case vertical
    }

    /// 이 구분선이 조절하는 방향.
    var axis: Axis = .horizontal
    /// 마우스 이동량(pt). 가로 방향은 오른쪽이, 세로 방향은 아래쪽이 양수다.
    let onDrag: (CGFloat) -> Void

    /// 마우스를 잡을 수 있는 두께. 1pt 선 양쪽으로 4pt씩 여유를 준다.
    private static let grabThickness: CGFloat = 9

    var body: some View {
        Rectangle()
            .fill(Palette.divider)
            .frame(width: axis == .horizontal ? 1 : nil,
                   height: axis == .vertical ? 1 : nil)
            .frame(maxWidth: axis == .vertical ? .infinity : nil,
                   maxHeight: axis == .horizontal ? .infinity : nil)
            .overlay {
                ResizeHandle(axis: axis, onDrag: onDrag)
                    .frame(width: axis == .horizontal ? Self.grabThickness : nil,
                           height: axis == .vertical ? Self.grabThickness : nil)
            }
    }
}

/// 리사이즈 커서를 커서 렉트로 등록하고, 드래그 이동량을 콜백으로 넘기는 뷰.
private struct ResizeHandle: NSViewRepresentable {
    let axis: ResizeDivider.Axis
    let onDrag: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HandleView()
        view.axis = axis
        view.onDrag = onDrag
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? HandleView else { return }
        view.onDrag = onDrag
        if view.axis != axis {
            view.axis = axis
            view.window?.invalidateCursorRects(for: view)
        }
    }

    private final class HandleView: NSView {
        var axis: ResizeDivider.Axis = .horizontal
        var onDrag: ((CGFloat) -> Void)?

        private var cursor: NSCursor {
            axis == .horizontal ? .resizeLeftRight : .resizeUpDown
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: cursor)
        }

        /// SwiftUI가 뷰를 재배치해도 커서 렉트가 새 bounds를 따라가게 한다.
        override func layout() {
            super.layout()
            window?.invalidateCursorRects(for: self)
        }

        /// 드래그가 구분선 밖으로 나가도 커서를 유지한다.
        /// mouseDown/mouseUp이 항상 쌍으로 오므로 커서 스택이 어긋나지 않는다.
        override func mouseDown(with event: NSEvent) {
            cursor.push()
        }

        override func mouseDragged(with event: NSEvent) {
            // deltaY는 마우스를 아래로 움직일 때 양수다(화면 좌표 기준).
            onDrag?(axis == .horizontal ? event.deltaX : event.deltaY)
        }

        override func mouseUp(with event: NSEvent) {
            NSCursor.pop()
        }
    }
}
