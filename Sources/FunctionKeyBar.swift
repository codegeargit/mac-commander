import SwiftUI

/// 화면 하단의 Function Key 바 — Total Commander의 시그니처 UI.
/// 듀얼 모드(트리 2개)에서 상태바 아래에 붙어, 반대편 트리로 복사·이동 같은 파일 작업 키를
/// 레트로 키캡 스타일 버튼으로 보여 준다. 클릭과 단축키 양쪽으로 동작한다.
struct FunctionKeyBar: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var theme: ThemeManager

    /// 한 개의 F-key 정의.
    private struct FKey: Identifiable {
        var id: String { key }
        let key: String
        let title: String
        /// 마우스를 올렸을 때 보여 줄 긴 설명(없으면 title).
        var help: String? = nil
        let enabled: Bool
        let action: () -> Void
    }

    private var keys: [FKey] {
        let hasCursor = store.cursorURL != nil
        let hasTargets = hasCursor || store.markedCount > 0
        // 복사·이동이 향하는 쪽. 보낼 것이 없으면 화살표를 붙이지 않는다.
        let source = store.transferSourcePaneIndex()
        let arrow = source.map { $0 == 0 ? " →" : " ←" } ?? ""
        // 같은 위치 열기는 활성 트리의 위치를 반대편으로 보내는 쪽만 보여 준다(반대 방향 키도 그대로 동작).
        // 버튼 둘을 두면 좁은 창에서 라벨이 잘린다.
        let toRight = store.activePaneIndex == 0
        return [
            FKey(key: "F3", title: loc.string(.fkeyView),
                 enabled: hasCursor || store.selectedURL != nil) { store.fkeyView() },
            FKey(key: "F4", title: loc.string(.fkeyEdit),
                 enabled: hasCursor || store.selectedURL != nil) { store.fkeyEdit() },
            FKey(key: "F5", title: loc.string(.fkeyCopy) + arrow,
                 help: loc.string(.fkeyCopyToOther),
                 enabled: source != nil) { store.fkeyCopyAtCursor() },
            FKey(key: "F6", title: loc.string(.fkeyMove) + arrow,
                 help: loc.string(.fkeyMoveToOther),
                 enabled: source != nil) { store.fkeyRenameAtCursor() },
            FKey(key: "⇧F6", title: loc.string(.fkeyRename),
                 enabled: hasCursor) { store.fkeyRenameInPlace() },
            FKey(key: "F7", title: loc.string(.fkeyNewFolder),
                 enabled: store.root != nil) { store.createFolderAtCursor() },
            FKey(key: "F8", title: loc.string(.fkeyDelete),
                 enabled: hasTargets) { store.requestDeleteAtCursor() },
            FKey(key: toRight ? "⌥⌘→" : "⌥⌘←", title: loc.string(.fkeySameLocation),
                 help: loc.string(toRight ? .menuSameLocationRight : .menuSameLocationLeft),
                 enabled: store.activePane.root != nil) { store.showSameLocation(inPane: toRight ? 1 : 0) },
        ]
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys) { key in
                FunctionKeyButton(
                    key: key.key,
                    title: key.title,
                    help: key.help ?? key.title,
                    enabled: key.enabled,
                    action: key.action
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            // 헤더와 같은 톤의 바탕 + 상단 1px 구분선으로 본문과 분리.
            Palette.headerBackground
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.divider).frame(height: 1)
                }
        )
    }
}

/// 레트로 키캡 스타일 버튼 하나. 좌측에 시안 키캡(F3), 우측에 라벨.
private struct FunctionKeyButton: View {
    @EnvironmentObject private var theme: ThemeManager
    let key: String
    let title: String
    let help: String
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                // 키캡: 움푹한 입체감(상단 하이라이트 + 하단 그림자)을 준 시안 캡.
                Text(key)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.selectForeground)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.accent)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                                    .blendMode(.plusLighter)
                            )
                            .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
                    )

                Text(title)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hovering ? Palette.accent.opacity(0.16) : Palette.panelBackground.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                hovering ? Palette.accent.opacity(0.7) : Palette.divider,
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(pressed ? 0.96 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 눌러도 키보드 포커스를 가져가지 않는다. 가져가면 트리의 화살표·Tab 조작이 끊긴다.
        .focusable(false)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 && enabled }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.08), value: pressed)
        // 누르는 순간의 미세한 눌림 피드백.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if enabled { pressed = true } }
                .onEnded { _ in pressed = false }
        )
        .help("\(key) · \(help)")
    }
}
