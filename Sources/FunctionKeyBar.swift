import SwiftUI

/// 화면 하단의 Function Key 바 — Total Commander의 시그니처 UI.
/// F3~F8을 레트로 키캡 스타일 버튼으로 보여주고, 클릭/단축키 양쪽으로 동작한다.
struct FunctionKeyBar: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var theme: ThemeManager

    /// 한 개의 F-key 정의.
    private struct FKey: Identifiable {
        let id = UUID()
        let n: Int
        let label: L10n
        let action: () -> Void
        let enabled: () -> Bool
    }

    private var keys: [FKey] {
        [
            FKey(n: 3, label: .fkeyView,      action: { store.fkeyView() },
                 enabled: { store.cursorURL != nil || store.selectedURL != nil }),
            FKey(n: 4, label: .fkeyEdit,      action: { store.fkeyEdit() },
                 enabled: { store.cursorURL != nil || store.selectedURL != nil }),
            FKey(n: 5, label: .fkeyCopy,      action: { store.fkeyCopyAtCursor() },
                 enabled: { store.cursorURL != nil }),
            FKey(n: 6, label: .fkeyRename,    action: { store.fkeyRenameAtCursor() },
                 enabled: { store.cursorURL != nil }),
            FKey(n: 7, label: .fkeyNewFolder, action: { store.createFolderAtCursor() },
                 enabled: { store.root != nil }),
            FKey(n: 8, label: .fkeyDelete,    action: { store.requestDeleteAtCursor() },
                 enabled: { store.cursorURL != nil }),
        ]
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys) { key in
                FunctionKeyButton(
                    number: key.n,
                    title: loc.string(key.label),
                    enabled: key.enabled(),
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
    let number: Int
    let title: String
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                // 키캡: 움푹한 입체감(상단 하이라이트 + 하단 그림자)을 준 시안 캡.
                Text("F\(number)")
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
        .help("F\(number) · \(title)")
    }
}
