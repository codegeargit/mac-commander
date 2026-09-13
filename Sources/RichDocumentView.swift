import SwiftUI
import Quartz

/// Word·Excel·PowerPoint·Apple iWork 문서를 QuickLook으로 보여주는 읽기 전용 뷰어.
///
/// 처음에는 `NSAttributedString(url:options:)`으로 직접 파싱했는데, 이 파서가
/// .docx 안의 이미지를 통째로 버린다(`w:drawing` 요소를 건너뛰어 NSTextAttachment가
/// 하나도 만들어지지 않는다). 텍스트·표·서식은 살아나지만 그림이 든 문서는 내용이
/// 반쪽이 되어 QLPreviewView로 옮겼다. Finder 미리보기와 같은 렌더러라
/// 원본에 가깝게 보이고 iWork 문서까지 덤으로 열린다.
///
/// 대신 렌더링을 QuickLook에 통째로 맡기므로 앱의 뷰어 기능(⌘F 찾기, 테마 배경,
/// 폰트 크기 조절)은 이 뷰 안에서 동작하지 않는다. 확대·스크롤·검색은 QuickLook이
/// 자체 UI로 제공한다.
struct RichDocumentView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        /// 이미 표시 중인 문서. 같으면 다시 넣지 않아 스크롤 위치가 유지된다.
        var appliedURL: URL?
        /// 문서 수정 시각. 외부에서 파일이 바뀌면 다시 읽는다.
        var appliedModified: TimeInterval = 0
    }

    func makeNSView(context: Context) -> QLPreviewView {
        // style: .normal은 미리보기 본문만 그린다(.compact는 Finder의 스페이스바 창처럼
        // 닫기 버튼과 테두리가 붙는다 — 패널 안에 끼워 넣기에는 .normal이 맞다).
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        // 기본값이 false라 명시하지 않으면 문서를 넣어도 렌더링이 시작되지 않는다.
        view.autostarts = true
        // 기본값 true면 창이 닫힐 때 뷰가 스스로 정리되는데, 패널을 옮기거나
        // 창을 오갈 때 미리보기가 빈 화면으로 남는 경우가 있어 끈다.
        view.shouldCloseWithWindow = false
        apply(view, context: context)
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        apply(view, context: context)
    }

    /// 문서를 반영한다. 같은 파일이고 수정도 없었으면 건드리지 않는다
    /// (previewItem을 다시 넣으면 스크롤이 맨 위로 튄다).
    private func apply(_ view: QLPreviewView, context: Context) {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        guard url != context.coordinator.appliedURL
                || modified != context.coordinator.appliedModified else { return }
        context.coordinator.appliedURL = url
        context.coordinator.appliedModified = modified
        view.previewItem = url as QLPreviewItem
        // 이미 표시 중인 문서를 갈아끼울 때는 갱신을 한 번 눌러 줘야 새 내용이 올라온다.
        view.refreshPreviewItem()
    }

    /// 뷰가 사라질 때 QuickLook 리소스를 정리한다.
    /// (shouldCloseWithWindow를 껐으므로 여기서 직접 닫아 준다.)
    static func dismantleNSView(_ view: QLPreviewView, coordinator: Coordinator) {
        view.close()
    }
}
