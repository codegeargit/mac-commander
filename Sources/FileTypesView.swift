import SwiftUI

/// 뷰어가 지원하는 파일 형식을 보여주는 도움말 창(시트). Help 메뉴에서 연다.
/// 확장자 목록은 FileNode의 상수에서 동적으로 만들어, 지원 형식이 늘어나면
/// 이 창도 자동으로 최신 상태가 된다(하드코딩 불일치 방지).
struct FileTypesView: View {
    @EnvironmentObject private var loc: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    /// 형식 한 줄: 설명 L10n + 확장자 목록(표시용 문자열).
    private struct TypeRow: Identifiable {
        let id = UUID()
        let icon: String
        let desc: L10n
        let extensions: String
    }

    /// Set<String> 확장자를 ".md .markdown" 형태의 표시 문자열로.
    private static func list(_ exts: Set<String>) -> String {
        exts.sorted().map { ".\($0)" }.joined(separator: "  ")
    }

    private var rows: [TypeRow] {
        [
            TypeRow(icon: "doc.text", desc: .ftMarkdown,
                    extensions: Self.list(FileNode.markdownExtensions)),
            TypeRow(icon: "globe", desc: .ftHTML,
                    extensions: Self.list(FileNode.htmlExtensions)),
            TypeRow(icon: "doc.richtext", desc: .ftPDF,
                    extensions: Self.list(FileNode.pdfExtensions)),
            TypeRow(icon: "photo", desc: .ftImage,
                    extensions: Self.list(FileNode.imageExtensions)),
            TypeRow(icon: "doc.richtext.fill", desc: .ftRichDoc,
                    extensions: Self.list(FileNode.richDocExtensions)),
            TypeRow(icon: "doc.plaintext", desc: .ftText,
                    extensions: loc.string(.ftTextExtensions)),
        ]
    }

    /// 앱 버전 문자열: "v1.5 (6)".
    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더 (ShortcutsView와 동일한 구성)
            HStack {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(Palette.accent)
                Text(loc.string(.fileTypesTitle))
                    .font(.system(size: 15, weight: .semibold))
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
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: row.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.accent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(loc.string(row.desc))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.textPrimary)
                                Text(row.extensions)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Palette.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Palette.viewerBackground)
        }
        .frame(width: 420, height: 380)
    }
}
