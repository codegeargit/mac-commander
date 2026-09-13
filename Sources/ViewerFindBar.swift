import SwiftUI

/// 뷰어 패널의 문서 내 찾기 바(⌘F). 헤더 바로 아래에 붙는다.
///
/// 입력할 때마다 첫 결과로 이동하고(증분 검색), Enter로 다음·⇧Enter로 이전,
/// Esc로 닫는다. 실제 검색은 각 뷰어가 수행한다(웹뷰는 `WKWebView.find`,
/// PDF는 `PDFDocument.findString`) — 여기서는 무엇을 찾을지만 스토어에 알린다.
struct ViewerFindBar: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager
    let panel: ViewerPanel
    let panelIndex: Int

    @FocusState private var fieldFocused: Bool

    private var queryBinding: Binding<String> {
        Binding(
            get: { store.panels[safe: panelIndex]?.findQuery ?? "" },
            set: { store.setFindQuery($0, panel: panelIndex) }
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textMuted)

            TextField(loc.string(.findPlaceholder), text: queryBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                // 결과가 없으면 입력 글자를 경고색으로 바꿔 즉시 알아채게 한다.
                .foregroundStyle(panel.findMissed ? Palette.textWarning : Palette.textPrimary)
                .focused($fieldFocused)
                .onSubmit { store.findAgain(panel: panelIndex, forward: true) }
                .onExitCommand { store.closeFind(panel: panelIndex) }
                // ⇧Enter는 위로 찾기. onSubmit은 수정자를 구분하지 못해 직접 본다.
                .onKeyPress(keys: [.return]) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    store.findAgain(panel: panelIndex, forward: false)
                    return .handled
                }

            if panel.findMissed {
                Text(loc.string(.findNoMatch))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textWarning)
            }

            barButton(icon: "chevron.up", help: loc.string(.findPrevious)) {
                store.findAgain(panel: panelIndex, forward: false)
            }
            barButton(icon: "chevron.down", help: loc.string(.findNext)) {
                store.findAgain(panel: panelIndex, forward: true)
            }
            barButton(icon: "xmark", help: loc.string(.findClose)) {
                store.closeFind(panel: panelIndex)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Palette.headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.divider).frame(height: 1)
        }
        // 바가 열리는 순간 입력에 포커스를 준다. ⌘F를 다시 눌러도 여기로 돌아온다.
        .onAppear { fieldFocused = true }
        .onChange(of: store.findFocusToken) { _, _ in
            if store.activePanelIndex == panelIndex { fieldFocused = true }
        }
    }

    private func barButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 18, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
