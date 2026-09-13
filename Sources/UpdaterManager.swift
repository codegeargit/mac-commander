import SwiftUI
import Sparkle

/// Sparkle 자동 업데이트 진입점.
///
/// `SPUStandardUpdaterController`가 백그라운드로 appcast(SUFeedURL)를 확인하고
/// 새 버전이 있으면 다운로드·EdDSA 검증·재설치까지 표준 UI로 처리한다.
/// 이 앱은 App Sandbox가 해제되어 있어 별도 XPC 설정이나 entitlement가 필요 없다.
///
/// SwiftUI `App`에서 한 번 생성해 보관하고, "업데이트 확인" 메뉴가 이 컨트롤러를
/// 통해 수동 확인을 트리거한다.
@MainActor
final class UpdaterManager: ObservableObject {
    /// Sparkle 표준 컨트롤러. startingUpdater: true 로 앱 시작 시 자동 확인을 켠다.
    let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater { controller.updater }
}

/// "업데이트 확인" 메뉴 버튼. updater가 확인 가능한 상태일 때만 활성화된다.
/// (초기화 직후나 확인 진행 중에는 canCheckForUpdates가 false가 된다.)
struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater
    private let title: String

    init(updater: SPUUpdater, title: String) {
        self.updater = updater
        self.title = title
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button(title) { updater.checkForUpdates() }
            .disabled(!viewModel.canCheckForUpdates)
    }
}

/// updater의 canCheckForUpdates를 관찰해 메뉴 활성화 상태를 SwiftUI에 반영한다.
@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
