import Foundation

/// Pro 라이선스가 있어야 쓸 수 있는 기능.
///
/// 무료 사용자가 이 기능을 건드리면 막기만 하지 않고 `ProUpsellView`로 무엇이 열리는지
/// 보여준다. 게이팅은 버튼·메뉴가 아니라 `WorkspaceStore`의 동작 하나하나에 건다.
/// 그래야 메뉴·단축키·헤더 버튼 어느 경로로 들어와도 한 곳에서 걸린다.
///
/// 무료로 남겨두는 것: 트리 탐색, 뷰어 1개, 편집·저장, 새 파일/폴더, 이름 변경, 삭제.
/// 앱을 평가하는 데 필요한 기본기는 막지 않는다.
enum ProFeature: String, Identifiable, CaseIterable {
    /// Pro 게이팅을 실제로 적용할지.
    ///
    /// **살 수 있을 때만 막는다**는 규칙을 코드로 고정한 것이다.
    /// 별도 플래그를 두면 라이브 전환 때 하나를 잊고 "구매 버튼은 없는데 기능은 막힌"
    /// 상태로 배포될 수 있다. 그 상태는 기존 사용자가 쓰던 기능을 잃고 되찾을 방법도 없는 최악이다.
    ///
    /// 그래서 구매 경로(`AppLinks.proCheckout`)의 유무에 묶어 둔다.
    /// - 릴리스 빌드: 라이브 체크아웃 주소를 채우기 전까지 nil → 게이팅 꺼짐(전 기능 무료)
    /// - Debug 빌드: 테스트 체크아웃 주소가 있으므로 게이팅 켜짐(동선 확인 가능)
    static var gatingEnabled: Bool { AppLinks.proCheckout != nil }

    /// 뷰어 패널을 2~3개로 분할.
    case multiPanel
    /// 내장 터미널 패널과 Claude Code 실행.
    case terminal
    /// 멀티 리네임(⌘R).
    case multiRename

    var id: String { rawValue }

    /// 기능 이름.
    var title: L10n {
        switch self {
        case .multiPanel:  return .proMultiPanel
        case .terminal:    return .proTerminal
        case .multiRename: return .proMultiRename
        }
    }

    /// 이 기능이 무엇을 해주는지 한 줄 설명.
    var detail: L10n {
        switch self {
        case .multiPanel:  return .proMultiPanelDetail
        case .terminal:    return .proTerminalDetail
        case .multiRename: return .proMultiRenameDetail
        }
    }

    /// 목록에 쓰는 SF Symbol 이름.
    var icon: String {
        switch self {
        case .multiPanel:  return "rectangle.split.3x1"
        case .terminal:    return "terminal"
        case .multiRename: return "textformat.abc"
        }
    }
}
