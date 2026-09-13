import SwiftUI

/// 앱에 포함된 오픈소스 구성요소의 저작권·라이선스 고지 창(시트). Help 메뉴에서 연다.
///
/// MIT/BSD 계열 라이선스는 배포물에 저작권 고지와 라이선스 전문을 포함할 것을 요구한다.
/// 전문은 Sources/Resources/licenses/*.txt 로 번들에 넣고 여기서 읽어 보여준다.
/// 의존성을 추가하면 그 라이선스 파일을 같은 폴더에 넣고 아래 `components`에 한 줄 추가한다.
struct AcknowledgementsView: View {
    @EnvironmentObject private var loc: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    /// 오픈소스 구성요소 하나.
    ///
    /// id는 파일 이름을 쓴다. UUID()로 만들면 body가 다시 그려질 때마다 값이 바뀌어
    /// 저장해둔 선택값과 어긋나고, 목록이 항상 첫 항목으로 되돌아간다.
    private struct Component: Identifiable {
        var id: String { file }
        /// 표시 이름.
        let name: String
        /// 앱이 실제로 포함한 버전(SPM은 Package.resolved, 번들 JS는 fetch 스크립트 기준).
        let version: String
        /// 라이선스 종류 표기.
        let license: String
        /// 프로젝트 홈페이지.
        let url: String
        /// Resources/licenses 안의 파일 이름(확장자 제외).
        let file: String
    }

    private static let components: [Component] = [
        Component(name: "Sparkle", version: "2.9.4", license: "MIT 외",
                  url: "https://sparkle-project.org", file: "sparkle"),
        Component(name: "SwiftTerm", version: "1.13.0", license: "MIT",
                  url: "https://github.com/migueldeicaza/SwiftTerm", file: "swiftterm"),
        Component(name: "MarkdownUI", version: "2.4.1", license: "MIT",
                  url: "https://github.com/gonzalezreal/swift-markdown-ui", file: "markdownui"),
        Component(name: "NetworkImage", version: "6.0.1", license: "MIT",
                  url: "https://github.com/gonzalezreal/NetworkImage", file: "networkimage"),
        Component(name: "swift-cmark", version: "0.8.0", license: "BSD-2-Clause 외",
                  url: "https://github.com/swiftlang/swift-cmark", file: "cmark"),
        Component(name: "marked", version: "14.1.2", license: "MIT",
                  url: "https://marked.js.org", file: "marked"),
        Component(name: "KaTeX", version: "0.16.11", license: "MIT",
                  url: "https://katex.org", file: "katex"),
        Component(name: "Mermaid", version: "11.16.0", license: "MIT",
                  url: "https://mermaid.js.org", file: "mermaid"),
    ]

    @State private var selection: String?

    /// 현재 선택된 구성요소(선택이 없으면 첫 항목).
    private var selected: Component {
        Self.components.first { $0.id == selection } ?? Self.components[0]
    }

    /// 번들에 넣어둔 라이선스 전문. 없으면 안내 문구로 대체한다.
    private func licenseText(_ component: Component) -> String {
        guard let url = Bundle.main.url(forResource: component.file, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return loc.string(.ackMissingText)
        }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더 (ShortcutsView·FileTypesView와 동일한 구성)
            HStack {
                Image(systemName: "text.book.closed")
                    .foregroundStyle(Palette.accent)
                Text(loc.string(.ackTitle))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(loc.string(.scClose)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Palette.headerBackground)

            Divider()

            // 좌: 구성요소 목록 / 우: 선택한 것의 라이선스 전문 — 앱의 2-pane과 같은 결.
            HStack(spacing: 0) {
                list
                Divider()
                detail
            }
        }
        .frame(width: 680, height: 470)
        .onAppear { selection = Self.components.first?.id }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Self.components) { component in
                    let isSelected = component.id == selected.id
                    VStack(alignment: .leading, spacing: 1) {
                        Text(component.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? Palette.selectForeground : Palette.textPrimary)
                        Text("\(component.version) · \(component.license)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(isSelected ? Palette.selectForeground : Palette.textMuted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isSelected ? Palette.selectBackground : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = component.id }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 200)
        .background(Palette.panelBackground)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(selected.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Link(selected.url, destination: URL(string: selected.url)!)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.accent)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                Text(licenseText(selected))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
            // 선택이 바뀌면 스크롤을 맨 위에서 다시 시작한다.
            .id(selected.id)

            Divider()
            Text(loc.string(.ackFootnote))
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.viewerBackground)
    }
}
