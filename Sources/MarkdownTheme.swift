import SwiftUI
import MarkdownUI

/// 레트로 Commander(다크+청색) 톤에 맞춘 MarkdownUI 테마.
/// 값은 Palette(디자인 토큰)과 동기화한다. GitHub 기본 테마 구조를 참고.
extension MarkdownUI.Theme {
    /// 본문 기준 폰트 크기를 받아 테마를 생성한다.
    /// 제목/코드/표 등은 `.em()` 상대 크기를 써서 base에 비례해 함께 조절된다.
    @MainActor
    static func retroCommander(baseSize: CGFloat) -> MarkdownUI.Theme {
        MarkdownUI.Theme()
        // 배경색은 지정하지 않는다. MarkdownUI는 text의 BackgroundColor를 글자 뒤가 아니라
        // 본문 블록 전체를 덮는 판으로 깔기 때문에, 이미지 뒤까지 색이 칠해져 튄다.
        // 뷰어 배경은 DocumentDetailView에서 이미 같은 색으로 칠하므로 여기선 불필요하다.
        .text {
            ForegroundColor(Palette.textPrimary)
            FontSize(baseSize)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.9))
            ForegroundColor(Palette.accent)
            BackgroundColor(Palette.codeInlineBackground)
        }
        // 본문색을 살짝 낮춰 둔 만큼, 볼드는 밝은 색으로 올려 강조를 살린다.
        .strong {
            FontWeight(.semibold)
            ForegroundColor(Palette.textHeading)
        }
        .link {
            ForegroundColor(Palette.accent)
        }
        // 본문 문단: 줄 간격을 넉넉히 주고 문단 사이 여백을 확보해 가독성을 높인다.
        // 한글은 라틴 문자보다 글자 밀도가 높아 줄 간격을 더 준다(줄높이 약 1.6배).
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.55))
                .markdownMargin(top: 0, bottom: 16)
        }
        // 목록: 항목 사이 간격과 목록 전후 여백.
        .list { configuration in
            configuration.label
                .markdownMargin(top: 4, bottom: 16)
        }
        .listItem { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.45))
                .markdownMargin(top: .em(0.5))
        }
        // 제목
        .heading1 { configuration in
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .relativePadding(.bottom, length: .em(0.3))
                    .markdownMargin(top: 40, bottom: 10)
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(2))
                        ForegroundColor(Palette.textHeading)
                    }
                Divider().overlay(Palette.divider)
            }
        }
        .heading2 { configuration in
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .relativePadding(.bottom, length: .em(0.3))
                    .markdownMargin(top: 34, bottom: 10)
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(1.5))
                        ForegroundColor(Palette.textHeading)
                    }
                Divider().overlay(Palette.divider)
            }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 28, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.25))
                    ForegroundColor(Palette.textFolder)
                }
        }
        .heading4 { configuration in
            configuration.label
                .markdownMargin(top: 22, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.05))
                    ForegroundColor(Palette.textFolder)
                }
        }
        // 코드 블록
        .codeBlock { configuration in
            if MermaidAsset.isMermaid(language: configuration.language) {
                // ```mermaid``` 는 텍스트가 아니라 실제 다이어그램으로 렌더링한다.
                MermaidView(source: configuration.content,
                            fontSize: baseSize,
                            isDark: Palette.isDark)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .markdownMargin(top: 8, bottom: 8)
            } else {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.9))
                        ForegroundColor(Palette.textPrimary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.codeBlockBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .markdownMargin(top: 8, bottom: 8)
            }
        }
        // 인용구
        .blockquote { configuration in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Palette.accentDim)
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle { ForegroundColor(Palette.textMuted) }
                    .padding(.leading, 12)
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 8, bottom: 8)
        }
        // 표
        .table { configuration in
            configuration.label
                .markdownTableBorderStyle(.init(color: Palette.divider))
                .markdownTableBackgroundStyle(
                    .alternatingRows(Palette.panelBackground, Palette.codeBlockBackground)
                )
                .markdownMargin(top: 8, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                        ForegroundColor(Palette.textFolder)
                    } else {
                        ForegroundColor(Palette.textPrimary)
                    }
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
        }
        // 수평선
        .thematicBreak {
            Divider()
                .overlay(Palette.divider)
                .markdownMargin(top: 12, bottom: 12)
        }
    }
}
