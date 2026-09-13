import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct MacCommanderApp: App {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var loc = LocalizationManager.shared
    @StateObject private var theme = ThemeManager.shared
    @StateObject private var license = LicenseManager.shared
    @StateObject private var updater = UpdaterManager()
    @Environment(\.colorScheme) private var systemScheme

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(loc)
                .environmentObject(theme)
                .environmentObject(license)
                .preferredColorScheme(theme.preferredColorScheme)
                .onAppear {
                    store.restoreSession()
                    license.restore()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // 앱 메뉴의 "MacCommander 정보": 표준 About 패널에 만든이 크레딧을 얹어서 띄운다.
            CommandGroup(replacing: .appInfo) {
                Button(loc.string(.menuAbout)) { showAboutPanel() }
            }
            CommandGroup(replacing: .newItem) {
                Button(loc.string(.newMarkdownFile)) { store.createMarkdownFileAtCursor() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(store.root == nil)
                Button(loc.string(.newFolder)) { store.createFolderAtCursor() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(store.root == nil)
                Divider()
                Button(loc.string(.delete)) { store.requestDeleteAtCursor() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(store.cursorURL == nil)
                Divider()
                Button(loc.string(.menuToggleEdit)) { store.toggleEditingActivePanel() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(store.selectedURL == nil)
                Button(loc.string(.menuSave)) { store.saveActivePanel() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!(store.panels[safe: store.activePanelIndex]?.isDirty ?? false))
                Divider()
                Button(loc.string(.menuOpenInTerminal)) { store.openInTerminalAtCursor() }
                    .keyboardShortcut("t", modifiers: .command)
                    .disabled(store.root == nil)
                Divider()
                Button(loc.string(.menuOpenFolder)) { store.promptOpenFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                Button(loc.string(.goToFolder)) { store.promptGoToFolder() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(store.root == nil)
                Button(loc.string(.menuQuickOpen)) { store.openQuickOpen() }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(store.root == nil)
            }
            // 인쇄 기능이 없다. 메뉴에서 빼서 ⌘P를 빠른 열기에 온전히 넘긴다.
            CommandGroup(replacing: .printItem) {}
            // 찾기는 macOS 관례대로 편집 메뉴(붙여넣기 다음)에 둔다.
            CommandGroup(after: .pasteboard) {
                Divider()
                Button(loc.string(.menuFind)) { store.openFind() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(!store.canFindInActivePanel)
                Button(loc.string(.menuFindNext)) { store.findNextInActivePanel() }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(!store.canFindInActivePanel)
                Button(loc.string(.menuContentSearch)) { store.openContentSearch() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(store.root == nil)
            }
            // Function Key 단축키 (Total Commander 스타일).
            // 메뉴 커맨드로 등록해 포커스(first responder) 위치와 무관하게 항상 동작.
            CommandMenu(loc.string(.menuCommands)) {
                Button("F3 · \(loc.string(.fkeyView))") { store.fkeyView() }
                    .keyboardShortcut(KeyEquivalent("\u{F706}"), modifiers: [])
                    .disabled(store.root == nil)
                Button("F4 · \(loc.string(.fkeyEdit))") { store.fkeyEdit() }
                    .keyboardShortcut(KeyEquivalent("\u{F707}"), modifiers: [])
                    .disabled(store.root == nil)
                Button("F5 · \(loc.string(.fkeyCopy))") { store.fkeyCopyAtCursor() }
                    .keyboardShortcut(KeyEquivalent("\u{F708}"), modifiers: [])
                    .disabled(store.cursorURL == nil)
                Button("F6 · \(loc.string(.fkeyRename))") { store.fkeyRenameAtCursor() }
                    .keyboardShortcut(KeyEquivalent("\u{F709}"), modifiers: [])
                    .disabled(store.cursorURL == nil)
                Button("F7 · \(loc.string(.fkeyNewFolder))") { store.createFolderAtCursor() }
                    .keyboardShortcut(KeyEquivalent("\u{F70A}"), modifiers: [])
                    .disabled(store.root == nil)
                Button("F8 · \(loc.string(.fkeyDelete))") { store.requestDeleteAtCursor() }
                    .keyboardShortcut(KeyEquivalent("\u{F70B}"), modifiers: [])
                    .disabled(store.cursorURL == nil)
                Divider()
                Button(proLabel(.mrtMenu)) { store.openMultiRename() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(store.cursorURL == nil && store.markedCount == 0)
            }
            // 보기 메뉴: 폰트 크기 / 패널 / 포커스 / 상위 폴더
            CommandGroup(after: .toolbar) {
                Button(loc.string(.menuFontLarger)) { store.increaseFont() }
                    .keyboardShortcut("+", modifiers: .command)  // ⌘+ (= 키 + Shift)
                Button(loc.string(.menuFontSmaller)) { store.decreaseFont() }
                    .keyboardShortcut("-", modifiers: .command)
                Button(loc.string(.menuFontDefault)) { store.resetFont() }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                Button(proLabel(.toggleTerminal)) { store.toggleTerminal() }
                    .keyboardShortcut("`", modifiers: .control)
                Button(loc.string(store.terminalPosition == .bottom
                                  ? .terminalMoveRight : .terminalMoveBottom)) {
                    store.toggleTerminalPosition()
                }
                .disabled(!store.showTerminal)
                Divider()
                Button(proLabel(.menuAddPanel)) { store.addPanel() }
                    .keyboardShortcut("+", modifiers: [.command, .control])
                    .disabled(!store.canAddPanel)
                Button(loc.string(.menuRemovePanel)) { store.removeActivePanel() }
                    .keyboardShortcut("-", modifiers: [.command, .control])
                    .disabled(!store.canRemovePanel)
                Divider()
                Button(loc.string(.menuFocusNext)) { store.focusNext() }
                    .keyboardShortcut(.tab, modifiers: [])
                Button(loc.string(.menuFocusPrevious)) { store.focusPrevious() }
                    .keyboardShortcut(.tab, modifiers: [.shift])
                Divider()
                Menu(loc.string(.sortMenu)) {
                    SortMenuItems()
                        .environmentObject(store)
                        .environmentObject(loc)
                }
                .disabled(store.root == nil)
                Divider()
                Button(loc.string(.goToParent)) { store.goToParent() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(!store.canGoToParent)
                Divider()
            }
            SidebarCommands()
            // Help 메뉴: 키보드 단축키 + 지원 파일 형식 + 오픈소스 고지 + 업데이트 확인.
            CommandGroup(replacing: .help) {
                Button(loc.string(.shortcutsMenu)) { store.showShortcuts = true }
                    .keyboardShortcut("/", modifiers: .command)
                Button(loc.string(.fileTypesMenu)) { store.showFileTypes = true }
                Button(loc.string(.ackMenu)) { store.showAcknowledgements = true }
                Divider()
                // 게이팅 전에는 안내할 Pro가 없다. 팔지도 않는 걸 광고하지 않는다.
                if ProFeature.gatingEnabled {
                    Button(loc.string(.proMenu)) { store.showProInfo = true }
                    Divider()
                }
                CheckForUpdatesView(updater: updater.updater,
                                    title: loc.string(.menuCheckForUpdates))
            }
        }

        // 환경설정 창 (⌘,)
        Settings {
            PreferencesView()
                .environmentObject(loc)
                .environmentObject(theme)
                .environmentObject(license)
        }
    }

    /// Pro 전용 메뉴 항목의 라벨. 무료 사용자에게만 "(Pro)"를 붙여
    /// 눌러보기 전에 유료 기능임을 알 수 있게 한다.
    private func proLabel(_ key: L10n) -> String {
        // 게이팅이 꺼져 있으면 실제로는 누구나 쓸 수 있으므로 (Pro) 표시가 거짓말이 된다.
        guard ProFeature.gatingEnabled, !license.isPro else { return loc.string(key) }
        return "\(loc.string(key)) (\(loc.string(.proSuffix)))"
    }

    /// macOS 표준 About 패널을 만든이 크레딧과 함께 띄운다.
    /// 별도 창을 만들지 않고 시스템 패널의 credits 영역만 채우는 방식.
    private func showAboutPanel() {
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let credits = NSMutableAttributedString(
            string: "\(loc.string(.madeBy))  ", attributes: baseAttrs)
        credits.append(NSAttributedString(
            string: "CodeGear",
            attributes: baseAttrs.merging([.link: AppLinks.github]) { _, new in new }))
        // 나머지 링크는 줄바꿈 한 번 뒤 " · "로 이어 붙여 한 줄에 담는다.
        for (index, item) in AppLinks.extras.enumerated() {
            credits.append(NSAttributedString(
                string: index == 0 ? "\n" : " · ", attributes: baseAttrs))
            credits.append(NSAttributedString(
                string: loc.string(item.label),
                attributes: baseAttrs.merging([.link: item.url]) { _, new in new }))
        }
        // 가운데 정렬(표준 패널의 다른 텍스트와 결을 맞춤).
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        credits.addAttribute(.paragraphStyle, value: center,
                             range: NSRange(location: 0, length: credits.length))

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
