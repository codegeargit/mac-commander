import SwiftUI

/// 멀티 리네임 시트 — Total Commander Multi-Rename Tool의 실용 핵심.
/// 마크된 항목들에 규칙(검색치환/연번/접두접미/대소문자)을 적용하고
/// 이전→이후를 실시간 미리보기로 보여준 뒤 일괄 적용한다.
struct MultiRenameView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var theme: ThemeManager

    @State private var rule = RenameRule()

    /// 실시간 미리보기.
    private var items: [RenamePreviewItem] {
        MultiRename.preview(urls: store.renameTargets, rule: rule)
    }
    private var changedCount: Int { items.filter { $0.changed && $0.issue == nil }.count }
    private var conflictCount: Int { items.filter { $0.issue != nil }.count }
    private var canApply: Bool { changedCount > 0 && conflictCount == 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.divider)

            HStack(alignment: .top, spacing: 0) {
                rulesPanel
                    .frame(width: 280)
                    .padding(14)
                Divider().overlay(Palette.divider)
                previewPanel
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            Divider().overlay(Palette.divider)
            footer
        }
        .frame(width: 720, height: 480)
        .background(Palette.panelBackground)
    }

    // MARK: 헤더

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "character.cursor.ibeam")
                .foregroundStyle(Palette.accent)
            Text(loc.string(.mrtTitle))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            Text(loc.string(.mrtTargetCount(store.renameTargets.count)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Palette.headerBackground)
    }

    // MARK: 규칙 패널(좌측)

    private var rulesPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 검색 → 치환
                section(loc.string(.mrtSearchReplace)) {
                    labeledField(loc.string(.mrtSearch), text: $rule.search)
                    labeledField(loc.string(.mrtReplace), text: $rule.replace)
                    Toggle(loc.string(.mrtRegex), isOn: $rule.useRegex)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11, design: .monospaced))
                    Toggle(loc.string(.mrtCaseInsensitive), isOn: $rule.caseInsensitive)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11, design: .monospaced))
                }

                // 접두/접미
                section(loc.string(.mrtAffix)) {
                    labeledField(loc.string(.mrtPrefix), text: $rule.prefix)
                    labeledField(loc.string(.mrtSuffix), text: $rule.suffix)
                }

                // 대소문자
                section(loc.string(.mrtCase)) {
                    Picker("", selection: $rule.caseMode) {
                        Text(loc.string(.mrtCaseKeep)).tag(RenameRule.CaseMode.keep)
                        Text(loc.string(.mrtCaseLower)).tag(RenameRule.CaseMode.lower)
                        Text(loc.string(.mrtCaseUpper)).tag(RenameRule.CaseMode.upper)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // 연번
                section(loc.string(.mrtCounter)) {
                    Toggle(loc.string(.mrtCounterEnable), isOn: $rule.counterEnabled)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11, design: .monospaced))
                    if rule.counterEnabled {
                        numberField(loc.string(.mrtCounterStart), value: $rule.counterStart)
                        numberField(loc.string(.mrtCounterStep), value: $rule.counterStep)
                        numberField(loc.string(.mrtCounterPad), value: $rule.counterPadding)
                        Text(loc.string(.mrtCounterHint))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.accent)
            content()
        }
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.textMuted)
                .frame(width: 52, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
        }
    }

    private func numberField(_ label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.textMuted)
                .frame(width: 52, alignment: .leading)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 64)
            Stepper("", value: value)
                .labelsHidden()
        }
    }

    // MARK: 미리보기 패널(우측)

    private var previewPanel: some View {
        VStack(spacing: 0) {
            // 컬럼 헤더
            HStack(spacing: 8) {
                Text(loc.string(.mrtColOld))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right").foregroundStyle(Palette.textMuted)
                Text(loc.string(.mrtColNew))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            .foregroundStyle(Palette.textMuted)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(Palette.headerBackgroundInactive)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        previewRow(item)
                    }
                }
            }
        }
        .background(Palette.viewerBackground)
    }

    private func previewRow(_ item: RenamePreviewItem) -> some View {
        HStack(spacing: 8) {
            Text(item.oldName)
                .foregroundStyle(Palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1).truncationMode(.middle)
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(Palette.divider)
            HStack(spacing: 5) {
                Text(item.newName)
                    .foregroundStyle(newNameColor(item))
                    .lineLimit(1).truncationMode(.middle)
                if let issue = item.issue {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .help(issueText(issue))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(item.issue != nil ? Color.orange.opacity(0.1) : Color.clear)
    }

    private func newNameColor(_ item: RenamePreviewItem) -> Color {
        if item.issue != nil { return .orange }
        if item.changed { return Palette.accent }   // 바뀐 이름 강조
        return Palette.textMuted                      // 무변경
    }

    private func issueText(_ issue: RenameIssue) -> String {
        switch issue {
        case .emptyName:    return loc.string(.mrtIssueEmpty)
        case .duplicate:    return loc.string(.mrtIssueDuplicate)
        case .invalidChars: return loc.string(.mrtIssueInvalid)
        }
    }

    // MARK: 푸터

    private var footer: some View {
        HStack(spacing: 12) {
            // 상태 요약
            if conflictCount > 0 {
                Label(loc.string(.mrtConflicts(conflictCount)), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label(loc.string(.mrtWillRename(changedCount)), systemImage: "checkmark.circle")
                    .foregroundStyle(changedCount > 0 ? Palette.accent : Palette.textMuted)
            }
            Spacer()
            Button(loc.string(.cancel)) { store.showMultiRename = false }
                .keyboardShortcut(.cancelAction)
            Button(loc.string(.mrtApply)) { store.applyMultiRename(items) }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Palette.headerBackground)
    }
}
