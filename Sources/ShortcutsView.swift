import SwiftUI

/// 키보드 단축키 + 마우스 규칙을 분류별로 보여주는 도움말 창(시트).
/// Help 메뉴에서 연다.
struct ShortcutsView: View {
    @EnvironmentObject private var loc: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    /// (단축키 표기, 설명 L10n) 한 줄.
    private struct Row: Identifiable {
        let id = UUID()
        let keys: String
        let desc: L10n
    }
    private struct Category: Identifiable {
        let id = UUID()
        let title: L10n
        let rows: [Row]
    }

    private var categories: [Category] {
        [
            Category(title: .scCategoryFile, rows: [
                Row(keys: "⌘N", desc: .scNewFile),
                Row(keys: "⇧⌘N", desc: .scNewFolder),
                Row(keys: "⌘⌫", desc: .scDelete),
                Row(keys: "⌘O", desc: .scOpenFolder),
                Row(keys: "⌘T", desc: .scOpenInTerminal),
                Row(keys: "⌘R", desc: .scMultiRename),
                Row(keys: "⌘↑", desc: .scGoParent),
                Row(keys: "⇧⌘G", desc: .scGoToFolder),
                Row(keys: "⌘P", desc: .scQuickOpen),
                Row(keys: "⇧⌘F", desc: .scContentSearch),
            ]),
            Category(title: .scCategoryViewer, rows: [
                Row(keys: "⌘F", desc: .scFind),
                Row(keys: "⌘G / Enter", desc: .scFindNext),
                Row(keys: "⇧Enter", desc: .scFindPrevious),
                Row(keys: "⌘E", desc: .scToggleEdit),
                Row(keys: "⌘S", desc: .scSave),
                Row(keys: "⌘+", desc: .scFontLarger),
                Row(keys: "⌘-", desc: .scFontSmaller),
                Row(keys: "⌘0", desc: .scFontReset),
                Row(keys: "⌘ + 휠", desc: .scZoomWheel),
            ]),
            Category(title: .scCategoryPanel, rows: [
                Row(keys: "⌃`", desc: .scToggleTerminal),
                Row(keys: "⌃⌘+", desc: .scAddPanel),
                Row(keys: "⌃⌘-", desc: .scRemovePanel),
                Row(keys: "⇥", desc: .scFocusNext),
                Row(keys: "⇧⇥", desc: .scFocusPrev),
            ]),
            Category(title: .scCategoryFKeys, rows: [
                Row(keys: "F3", desc: .fkeyView),
                Row(keys: "F4", desc: .fkeyEdit),
                Row(keys: "F5", desc: .fkeyCopy),
                Row(keys: "F6", desc: .fkeyRename),
                Row(keys: "F7", desc: .fkeyNewFolder),
                Row(keys: "F8", desc: .fkeyDelete),
                Row(keys: "Space / Insert", desc: .scMouseToggle),
            ]),
            Category(title: .scCategoryMouse, rows: [
                Row(keys: "Click", desc: .scMouseOpen),
                Row(keys: "⌘ Click", desc: .scMouseNewPanel),
                Row(keys: "⌥ Click", desc: .scMouseToggle),
                Row(keys: "⇧ Click", desc: .scMouseRange),
                Row(keys: "Drag", desc: .scMousePanelDrag),
            ]),
        ]
    }

    /// 앱 버전 문자열: "v1.4 (5)" — 마케팅 버전 + 빌드 번호.
    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Image(systemName: "keyboard")
                    .foregroundStyle(Palette.accent)
                Text(loc.string(.shortcutsTitle))
                    .font(.system(size: 15, weight: .semibold))
                // 현재 앱 버전(자동 업데이트 확인 시 참고용).
                Text(appVersion)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                Button(loc.string(.scClose)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Palette.headerBackground)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(categories) { cat in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(loc.string(cat.title))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Palette.accent)
                            ForEach(cat.rows) { row in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(row.keys)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Palette.textPrimary)
                                        .frame(width: 110, alignment: .leading)
                                    Text(loc.string(row.desc))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.textPrimary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Palette.viewerBackground)

            Divider()

            // 푸터: 만든이 표기 + 제작자 링크(GitHub · 유튜브 · 블로그).
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                Text(loc.string(.madeBy))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
                Link("CodeGear", destination: AppLinks.github)
                    .font(.system(size: 11, weight: .semibold))
                ForEach(AppLinks.extras, id: \.url) { item in
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textMuted)
                    Link(loc.string(item.label), destination: item.url)
                        .font(.system(size: 11))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Palette.headerBackground)
        }
        .frame(width: 460, height: 560)
    }
}
