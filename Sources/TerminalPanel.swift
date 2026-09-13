import SwiftUI
import SwiftTerm

/// Shift+Enter를 claude 같은 TUI가 "줄바꿈"으로 알아듣는 시퀀스로 바꿔 보내는 터미널 뷰.
///
/// 터미널 프로토콜에는 Shift+Enter라는 개념이 없어서, AppKit이 Shift+Return을
/// insertNewline으로 흡수해 버리면 SwiftTerm은 CR(0x0D) 한 바이트만 보낸다.
/// 받는 쪽에서는 그냥 Enter와 구분이 안 되므로 메시지가 전송돼 버린다.
/// claude의 `/terminal-setup`이 iTerm2·Terminal.app에 심는 키 매핑과 같은 일을
/// 여기서 직접 해준다.
final class CommanderTerminalView: LocalProcessTerminalView {
    /// Return 키의 keyCode(kVK_Return).
    private static let returnKeyCode: UInt16 = 36

    /// 설치해 둔 키 이벤트 모니터(해제용 토큰).
    private var keyMonitor: Any?

    /// Shift+Return을 가로채는 이벤트 모니터를 설치한다.
    ///
    /// keyDown은 SwiftTerm이 `public`(open 아님)으로 선언해 재정의할 수 없고,
    /// performKeyEquivalent는 ⌘ 계열 수정자가 없으면 AppKit이 아예 호출하지 않는다.
    /// 그래서 앱 이벤트 큐에서 먼저 낚아채는 로컬 모니터를 쓴다.
    func installShiftEnterMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleShiftEnter(event) else { return event }
            return nil   // 처리했으므로 이벤트를 소비한다.
        }
    }

    /// 설치한 모니터를 해제한다(뷰가 사라질 때 호출).
    func removeShiftEnterMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    deinit { removeShiftEnterMonitor() }

    /// Shift+Return이면 줄바꿈 시퀀스를 직접 보내고 true를 돌려준다.
    private func handleShiftEnter(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Shift만 눌린 Return일 때만 가로챈다(⌘/⌃/⌥ 조합은 원래 동작 유지).
        guard event.keyCode == Self.returnKeyCode,
              mods.contains(.shift),
              !mods.contains(.command), !mods.contains(.control), !mods.contains(.option),
              hasKeyboardFocus else { return false }

        if terminal != nil, !terminal.keyboardEnhancementFlags.isEmpty {
            // kitty keyboard protocol이 켜진 상태: 수정자를 실은 CSI u로 보낸다(13=Enter, 2=Shift).
            send(Array("\u{1b}[13;2u".utf8))
        } else {
            // 일반 상태: ESC + CR — /terminal-setup이 심는 것과 동일한 시퀀스.
            send([0x1b, 0x0d])
        }
        return true
    }

    /// 모니터는 앱 전체 키 입력을 보므로, 실제로 이 터미널이
    /// 키 입력을 받는 상태일 때만 가로채도록 확인한다.
    private var hasKeyboardFocus: Bool {
        guard let window, window.isKeyWindow,
              let responder = window.firstResponder as? NSView else { return false }
        return responder === self || responder.isDescendant(of: self)
    }
}

/// SwiftTerm의 LocalProcessTerminalView를 SwiftUI로 감싼 터미널 패널.
/// 앱 안에서 실제 로그인 셸을 pseudo-terminal로 실행한다(App Sandbox 해제 전제).
/// 지정한 폴더(workingDirectory)에서 셸을 시작한다.
struct TerminalView: NSViewRepresentable {
    /// 셸을 시작할 작업 디렉터리(보통 현재 워크스페이스 루트).
    let workingDirectory: String?
    /// 셸 프로세스가 종료(exit 등)됐을 때 호출 — 터미널 패널을 닫는다.
    var onProcessTerminated: () -> Void = {}
    /// 셸이 준비되면 자동으로 입력할 명령(예: "claude"). nil이면 아무것도 안 함.
    /// 소비 후 호출자가 상태를 지우도록 onCommandConsumed로 알린다.
    var autoCommand: String? = nil
    /// autoCommand를 셸에 주입한 뒤 호출 — 호출자가 pending 상태를 정리한다.
    var onCommandConsumed: () -> Void = {}
    /// 실행 중인 셸에 명령을 즉시 주입하는 콜백을 등록/해제한다.
    /// (터미널이 이미 열린 상태에서 Claude 버튼을 눌렀을 때 사용)
    var onSinkReady: ((((String) -> Void)?) -> Void) = { _ in }
    /// 앱 테마에 맞춘 터미널 배경/전경/커서 색. 테마가 바뀌면 값이 갱신돼 재적용된다.
    var themeColors: (background: NSColor, foreground: NSColor, cursor: NSColor)
    /// 터미널 글자 크기(pt). ⌘+/⌘- 또는 ⌘+휠로 바뀌면 값이 갱신돼 재적용된다.
    var fontSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(onProcessTerminated: onProcessTerminated)
    }

    func makeNSView(context: Context) -> CommanderTerminalView {
        let view = CommanderTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.installShiftEnterMonitor()
        applyTheme(to: view)
        applyFont(to: view)
        startShell(in: view)

        // 실행 중 주입용 sink 등록: 명령 뒤에 개행을 붙여 즉시 실행되게 한다.
        // 명령을 보내면서 포커스도 터미널로 되돌린다(버튼 클릭으로 포커스가 옮겨간 상태 대응).
        onSinkReady { [weak view] command in
            view?.send(txt: command + "\n")
            view?.window?.makeFirstResponder(view)
        }
        // 뷰가 사라지면 sink를 해제(nil 등록)하도록 예약.
        context.coordinator.onDismantle = { onSinkReady(nil) }

        // 뷰가 window에 붙은 뒤 키보드 포커스를 터미널로 넘긴다.
        // (makeNSView 시점에는 아직 window가 없어 다음 런루프로 미룬다)
        DispatchQueue.main.async { [weak view] in
            view?.window?.makeFirstResponder(view)
        }

        // 터미널이 열리는 시점에 예약된 자동 명령이 있으면 셸 프롬프트가
        // 올라온 뒤 주입한다. 셸 초기화(프로필 로드)에 시간이 걸리므로 약간 지연.
        if let command = autoCommand {
            let onConsumed = onCommandConsumed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak view] in
                view?.send(txt: command + "\n")
                // 명령 주입 후에도 포커스를 다시 확실히 잡는다.
                view?.window?.makeFirstResponder(view)
                onConsumed()
            }
        }
        return view
    }

    func updateNSView(_ view: CommanderTerminalView, context: Context) {
        // 최신 콜백을 유지(패널 재렌더 대응).
        context.coordinator.onProcessTerminated = onProcessTerminated
        // 테마가 바뀌면(themeColors 변경) 배경/전경/커서 색을 다시 적용한다.
        applyTheme(to: view)
        applyFont(to: view)
    }

    /// 터미널 글자 크기를 적용한다. 같은 크기면 건드리지 않는다 —
    /// font를 다시 넣으면 SwiftTerm이 셀 크기를 재계산하고 화면을 다시 그린다.
    private func applyFont(to view: LocalProcessTerminalView) {
        let target = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        guard view.font.pointSize != target.pointSize else { return }
        view.font = target
    }

    /// 앱 테마 색을 터미널 뷰에 적용한다. 배경/전경/커서를 모두 맞춘다.
    private func applyTheme(to view: LocalProcessTerminalView) {
        view.nativeBackgroundColor = themeColors.background
        view.nativeForegroundColor = themeColors.foreground
        view.caretColor = themeColors.cursor
        // 레이어 배경도 맞춰 스크롤 여백 등에서 이질감이 없게 한다.
        view.layer?.backgroundColor = themeColors.background.cgColor
    }

    static func dismantleNSView(_ view: CommanderTerminalView, coordinator: Coordinator) {
        // 뷰가 사라지면 등록해 둔 주입 sink와 키 이벤트 모니터를 해제한다.
        coordinator.onDismantle?()
        view.removeShiftEnterMonitor()
    }

    /// SwiftTerm 프로세스 이벤트를 받는 델리게이트.
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var onProcessTerminated: () -> Void
        /// 뷰 해제 시 sink 정리용 콜백.
        var onDismantle: (() -> Void)?

        init(onProcessTerminated: @escaping () -> Void) {
            self.onProcessTerminated = onProcessTerminated
        }

        // 셸 프로세스 종료 → 패널 닫기.
        // 주의: SwiftTerm의 TerminalView와 이 파일의 struct TerminalView가 이름이
        // 겹치므로 SwiftTerm.TerminalView로 명시한다.
        func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
            Task { @MainActor in onProcessTerminated() }
        }

        // 나머지 델리게이트 요구 메서드(동작 불필요, 기본 무시).
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
    }

    /// 사용자의 로그인 셸을 인터랙티브 로그인 모드로 띄운다.
    private func startShell(in view: LocalProcessTerminalView) {
        let env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        let shell = shellPath()
        let shellName = (shell as NSString).lastPathComponent

        if let dir = workingDirectory {
            FileManager.default.changeCurrentDirectoryPath(dir)
        }
        // 로그인 셸(-<shellName>)로 실행해 프로필(.zprofile 등)을 로드한다.
        view.startProcess(executable: shell, args: [], environment: env, execName: "-\(shellName)")
    }

    /// 사용자 로그인 셸 경로. $SHELL 우선, 없으면 zsh 폴백.
    private func shellPath() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }
        return "/bin/zsh"
    }
}

/// 헤더 바 + 터미널을 담은 우측 세로 패널.
struct TerminalPanel: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager
    // 테마 변경을 관찰해 터미널 색을 다시 넘긴다(updateNSView에서 재적용).
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        VStack(spacing: 0) {
            header
            // 터미널이 열리는 시점의 트리 커서 폴더에서 셸을 시작한다.
            // (패널 생성 시 한 번 캡처 — 이후 커서가 바뀌어도 실행 중 셸은 유지)
            TerminalView(
                workingDirectory: store.terminalStartDirectory.path,
                onProcessTerminated: { store.showTerminal = false },
                autoCommand: store.pendingTerminalCommand,
                onCommandConsumed: { store.pendingTerminalCommand = nil },
                onSinkReady: { store.terminalCommandSink = $0 },
                themeColors: theme.terminalColors,
                fontSize: store.terminalFontSize
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.viewerBackground)
        // ⌘+휠 확대 대상을 정하기 위해 마우스가 이 패널에 있음을 알린다.
        .onHover { inside in
            if inside { store.hoverArea = .terminal }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .foregroundStyle(Palette.accent)
            Text(loc.string(.terminalTitle))
                .font(.system(size: Palette.treeFontSize, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            positionButton
            Rectangle().fill(Palette.divider).frame(width: 1, height: 14)
            fontControls
            Rectangle().fill(Palette.divider).frame(width: 1, height: 14)
            Button(action: { store.toggleTerminal() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(height: 22)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc.string(.closePanel))
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Palette.headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.divider).frame(height: 1)
        }
    }

    /// 터미널을 오른쪽 ↔ 아래로 옮기는 버튼. 아이콘은 **누르면 갈 자리**를 보여준다.
    /// 실행 중인 셸은 유지된다(레이아웃만 바뀐다).
    private var positionButton: some View {
        let atBottom = store.terminalPosition == .bottom
        return headerButton(
            help: loc.string(atBottom ? .terminalMoveRight : .terminalMoveBottom),
            action: { store.toggleTerminalPosition() }
        ) {
            Image(systemName: atBottom ? "square.righthalf.filled" : "square.bottomhalf.filled")
                .font(.system(size: 12))
        }
    }

    /// 터미널 글자 크기 컨트롤. 이 버튼들은 대상이 분명하므로 포커스와 무관하게
    /// 항상 터미널에만 적용한다(단축키 ⌘+/⌘-는 포커스한 쪽에 적용된다).
    private var fontControls: some View {
        HStack(spacing: 1) {
            headerButton(help: loc.string(.fontSmaller), action: store.decreaseTerminalFont) {
                Image(systemName: "textformat.size.smaller").font(.system(size: 12))
            }
            headerButton(help: loc.string(.fontReset), action: store.resetTerminalFont) {
                Text("\(Int(store.terminalFontSize))")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 18)
            }
            headerButton(help: loc.string(.fontLarger), action: store.increaseTerminalFont) {
                Image(systemName: "textformat.size.larger").font(.system(size: 12))
            }
        }
    }

    private func headerButton<Label: View>(
        help: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(Palette.accent)
                .frame(height: 22)
                .padding(.horizontal, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
