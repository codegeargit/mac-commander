import SwiftUI
import UniformTypeIdentifiers
import MarkdownUI

/// 우측 마크다운 뷰어 패널 하나. 열린 파일 본문을 폭에 맞춰 렌더링한다.
struct DocumentDetailView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var theme: ThemeManager
    let panel: ViewerPanel
    let panelIndex: Int
    let isActive: Bool
    /// 패널이 2개 이상일 때만 활성 표시(헤더 강조)와 닫기 버튼을 보여준다.
    let showActiveIndicator: Bool

    /// 트리에서 파일을 이 패널로 드래그 중인지(드롭 하이라이트).
    @State private var isDropTargeted = false
    /// 다른 패널을 이 패널 헤더로 드래그 중인지(순서 교환 하이라이트).
    @State private var isPanelDropTargeted = false

    /// 편집 모드에서 TextEditor가 바인딩할 초안 텍스트(스토어 패널로 위임).
    private var draftBinding: Binding<String> {
        Binding(
            get: { store.panels[safe: panelIndex]?.draft ?? "" },
            set: { newValue in
                guard store.panels.indices.contains(panelIndex) else { return }
                store.panels[panelIndex].draft = newValue
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            // 문서 내 찾기 바(⌘F). 헤더 바로 아래에 붙는다.
            if panel.showFind {
                ViewerFindBar(panel: panel, panelIndex: panelIndex)
                    .environmentObject(store)
                    .environmentObject(loc)
            }

            if panel.isPDF, let url = panel.fileURL {
                // PDF: PDFKit으로 렌더링(편집/평문 표시 없음). 배율은 패널 상태로.
                // Cmd+휠로 바뀐 배율은 onZoom으로 스토어에 반영.
                PDFViewer(url: url, zoom: panel.pdfZoom,
                          onZoom: { store.setPDFZoom(panel: panelIndex, to: $0) },
                          findRequest: panel.findRequest,
                          onFindResult: { found in
                              store.reportFindResult(found: found, panel: panelIndex)
                          },
                          onPageChange: { page, total in
                              store.setPDFPage(panel: panelIndex, page: page, of: total)
                          })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.viewerBackground)
            } else if panel.isImage, let url = panel.fileURL {
                // 이미지: 맞춤(가로·세로) + 가운데 정렬로 렌더링. PDF와 동일한 배율 상태를 공유.
                // onFitScale로 맞춤 모드의 실제 배율을 받아 헤더에 %로 표시.
                ImageViewer(url: url, zoom: panel.pdfZoom,
                            onZoom: { store.setPDFZoom(panel: panelIndex, to: $0) },
                            onFitScale: { store.setImageFitScale(panel: panelIndex, to: $0) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.viewerBackground)
            } else if panel.isEditing {
                editor
            } else if panel.isHTML, let url = panel.fileURL {
                // HTML: WebView로 파일을 그대로 렌더링(브라우저처럼).
                // 편집 모드(⌘E)에서는 위 editor 분기가 원문 소스를 보여준다.
                HTMLWebView(fileURL: url,
                            findRequest: panel.findRequest,
                            onFindResult: { found in
                                store.reportFindResult(found: found, panel: panelIndex)
                            })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.viewerBackground)
            } else if panel.isRichDoc, let pdf = panel.richDocPDF, !panel.prefersQuickLook {
                // 변환이 끝난 서식 문서: PDF로 보여 준다. QuickLook과 달리 표 폭·글꼴이
                // 원본대로 나오고, PDFKit이라 ⌘F 찾기와 확대/축소도 함께 살아난다.
                PDFViewer(url: pdf, zoom: panel.pdfZoom,
                          onZoom: { store.setPDFZoom(panel: panelIndex, to: $0) },
                          findRequest: panel.findRequest,
                          onFindResult: { found in
                              store.reportFindResult(found: found, panel: panelIndex)
                          },
                          onPageChange: { page, total in
                              store.setPDFPage(panel: panelIndex, page: page, of: total)
                          })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.viewerBackground)
            } else if panel.isRichDoc, let url = panel.fileURL {
                // 변환 전(또는 변환 불가): QuickLook으로 먼저 보여 준다. 바로 뜨는 대신
                // 표가 있는 문서는 열 폭이 원본과 다를 수 있다.
                RichDocumentView(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.viewerBackground)
            } else if let content = panel.content, panel.isPlainText {
                // 마크다운이 아닌 파일: 렌더링하지 않고 평문(고정폭)으로 표시.
                // 로그·CSV·코드가 모두 이 경로로 오므로 열 정렬이 깨지지 않게
                // 고정폭과 폭 제한 없음을 유지하고, 줄 간격·여백만 넉넉히 준다.
                PlainTextView(text: content,
                              fontSize: store.viewerFontSize,
                              colors: theme.colors,
                              findRequest: panel.findRequest,
                              onFindResult: { found in
                                  store.reportFindResult(found: found, panel: panelIndex)
                              },
                              // 트랙패드 핀치는 ⌘+/⌘- 와 같은 글자 크기 조절로 잇는다.
                              onZoomStep: { step in
                                  if step > 0 { store.increaseViewerFont() }
                                  else { store.decreaseViewerFont() }
                              })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.viewerBackground)
            } else if let content = panel.content {
                // 마크다운: WKWebView(marked.js + KaTeX + mermaid)로 렌더링한다.
                // MarkdownUI는 LaTeX 수식을 지원하지 않아 WebView 렌더러로 전환했다.
                // 읽기 폭 제한·좌우 여백·스크롤은 HTML/CSS(#content max-width) 안에서 처리하므로
                // 여기서는 WebView가 패널 영역을 꽉 채우게만 한다.
                // baseURL로 문서 폴더를 넘겨야 `![](./images/foo.png)` 상대 경로가 해석된다.
                MarkdownWebView(
                    content: content,
                    fileURL: panel.fileURL,
                    fontSize: store.viewerFontSize,
                    colors: theme.colors,
                    isDark: theme.isDark,
                    // 읽던 위치는 문서별로 스토어가 기억한다(폰트·테마 변경, 편집 왕복 대비).
                    scrollRatio: { store.viewerScrollRatio(for: panel.fileURL) },
                    onScroll: { ratio in
                        Task { @MainActor in store.setViewerScrollRatio(ratio, for: panel.fileURL) }
                    },
                    // 문서 안의 로컬 문서 링크는 이 패널에서 이어 읽는다.
                    onOpenFile: { url in
                        Task { @MainActor in store.openMarkdown(at: url, inPanel: panelIndex) }
                    },
                    findRequest: panel.findRequest,
                    onFindResult: { found in
                        store.reportFindResult(found: found, panel: panelIndex)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.viewerBackground)
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(Palette.textMuted)
                    Text(loc.string(.selectFilePrompt))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Palette.viewerBackground)
        // ⌘+휠 확대 대상을 정하기 위해 마우스가 이 패널에 있음을 알린다.
        .onHover { inside in
            if inside { store.hoverArea = .panel(panelIndex) }
        }
        // 트리에서 마크다운 파일을 이 패널로 드롭하면 이 패널에 연다.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return store.openMarkdown(at: url, inPanel: panelIndex)
        } isTargeted: { hovering in
            isDropTargeted = hovering
        }
        .overlay {
            if isDropTargeted {
                Rectangle()
                    .strokeBorder(Palette.accent, lineWidth: 2)
                    .background(Palette.accent.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
    }

    /// 편집 모드 본문: 고정폭 텍스트 에디터. 폰트 크기는 뷰어와 공유.
    /// 줄 간격도 평문 뷰어와 맞춰 편집/미리보기를 오갈 때 밀도가 튀지 않게 한다.
    private var editor: some View {
        TextEditor(text: draftBinding)
            .font(.system(size: store.viewerFontSize, design: .monospaced))
            .lineSpacing(store.viewerFontSize * 0.35)
            .foregroundStyle(Palette.textPrimary)
            .scrollContentBackground(.hidden)
            .background(Palette.viewerBackground)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.viewerBackground)
    }

    /// 헤더 바: (활성 표시) 파일명 + 폰트/패널 컨트롤.
    private var header: some View {
        HStack(spacing: 6) {
            titleDragHandle
            Spacer()

            // 편집/저장 컨트롤 (편집 가능한 파일이 열려 있을 때만.
            // PDF·이미지·서식 문서는 읽기 전용이라 제외)
            if panel.fileURL != nil && !panel.isPDF && !panel.isImage && !panel.isRichDoc {
                editControls
                divider
            }
            // 서식 문서를 더 정확한 PDF로 바꾸는 중이라는 표시.
            if panel.isConverting {
                convertingIndicator
            }
            // 렌더러 전환 (변환본이 준비된 서식 문서에서만).
            // 두 렌더러가 어긋나는 방식이 달라 문서마다 나은 쪽이 다르다.
            if panel.isRichDoc && panel.richDocPDF != nil {
                rendererToggle
            }
            // 폰트 크기 컨트롤 (텍스트 계열 파일일 때만.
            // 서식 문서는 QuickLook·PDF가 자체 확대를 제공하므로 제외)
            if panel.content != nil {
                fontControls
            }
            // 쪽 표시 (PDF 계열에서 문서를 읽고 나면 채워진다)
            if panel.showsPDF && panel.pdfPageCount > 0 {
                pageIndicator
            }
            // PDF·이미지 확대/축소 컨트롤 (배율 상태 공유)
            if panel.showsPDF || panel.isImage {
                pdfZoomControls
            }
            // 패널 추가 + 터미널 토글은 활성 패널에만 표시(중복 방지)
            if isActive {
                if panel.content != nil || panel.showsPDF || panel.isImage || panel.isRichDoc { divider }
                if store.canAddPanel { addPanelButton }
                terminalToggleButton
                claudeCodeButton
            }
            // 닫기(X)는 패널이 2개 이상일 때 각 패널마다
            if store.canRemovePanel {
                closeButton
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(headerBackground)
        // 다른 패널 헤더를 이 헤더로 드롭하면 두 패널 위치를 맞바꾼다.
        // (.draggable 대신 NSItemProvider 기반 onDrag/onDrop — macOS에서 더 안정적)
        .onDrop(of: [.plainText], isTargeted: Binding(
            get: { isPanelDropTargeted },
            set: { isPanelDropTargeted = $0 }
        )) { providers in
            handlePanelDrop(providers)
        }
        .overlay(alignment: .bottom) {
            // 활성 패널은 청색 하단 경계, 비활성은 일반 구분선 — 높이 변화 없음.
            Rectangle()
                .fill(showActiveIndicator && isActive ? Palette.accent : Palette.divider)
                .frame(height: showActiveIndicator && isActive ? 2 : 1)
        }
        .overlay {
            // 순서 교환 드롭 대상 강조.
            if isPanelDropTargeted {
                Rectangle().fill(Palette.accent.opacity(0.18)).allowsHitTesting(false)
            }
        }
    }

    /// 헤더 좌측: 아이콘 + 파일명 + 변경 배지. 이 영역을 잡고 드래그하면 패널 순서를 바꾼다.
    private var titleDragHandle: some View {
        HStack(spacing: 6) {
            Image(systemName: headerIconName)
                .foregroundStyle(Palette.accent)
            Text(panel.fileName ?? "—")
                .font(.system(size: Palette.treeFontSize, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
            // 저장하지 않은 변경 표시.
            if panel.isDirty {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 6, height: 6)
                    .help(loc.string(.unsavedBadge))
            }
        }
        .contentShape(Rectangle())
        // 헤더를 잡고 드래그하면 이 패널 인덱스를 문자열로 실어 보낸다.
        .onDrag {
            NSItemProvider(object: "\(Self.panelMovePrefix)\(panelIndex)" as NSString)
        }
    }

    /// 서식 문서의 렌더러 전환 버튼(변환 PDF ↔ QuickLook).
    /// 변환 PDF는 표 폭·글꼴이 정확한 대신 사진이 많은 표에서 페이지 경계에 걸린 행이
    /// 갈라지고, QuickLook은 그 문제가 없는 대신 표 폭이 뭉친다. 문서마다 나은 쪽이
    /// 달라 사용자가 눈으로 보고 고르게 한다.
    private var rendererToggle: some View {
        headerButton(
            help: loc.string(panel.prefersQuickLook ? .useConvertedLayout : .useQuickLookLayout),
            action: { store.toggleRichDocRenderer(panel: panelIndex) }
        ) {
            Image(systemName: panel.prefersQuickLook ? "doc.text.magnifyingglass" : "tablecells")
                .font(.system(size: 12))
        }
    }

    /// 헤더의 쪽 표시 ("3 / 12"). 스크롤에 따라 현재 쪽이 갱신된다.
    /// 숫자 폭이 흔들리지 않게 고정폭 숫자를 쓴다.
    private var pageIndicator: some View {
        Text("\(panel.pdfPage) / \(panel.pdfPageCount)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Palette.textMuted)
            .monospacedDigit()
            .help(loc.string(.pageIndicatorHelp))
    }

    /// 서식 문서를 PDF로 변환하는 동안 헤더에 띄우는 표시.
    /// 지금 보이는 QuickLook 화면이 잠시 뒤 더 정확한 것으로 바뀐다는 예고다.
    private var convertingIndicator: some View {
        HStack(spacing: 4) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)
            Text(loc.string(.convertingDocument))
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
        }
        .help(loc.string(.convertingDocumentHelp))
    }

    /// 헤더 좌측 파일 종류 아이콘(PDF·이미지·서식 문서·텍스트).
    private var headerIconName: String {
        if panel.isPDF { return "doc.richtext" }
        if panel.isImage { return "photo" }
        if panel.isRichDoc { return "doc.plaintext" }
        return "doc.text"
    }

    /// 패널 순서 교환 드래그 페이로드 접두사(트리 파일 URL 드롭과 구분).
    private static let panelMovePrefix = "mc-panel-move:"

    /// 헤더로 드롭된 항목이 패널 이동이면 스왑을 수행한다.
    private func handlePanelDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let str = obj as? String,
                  str.hasPrefix(Self.panelMovePrefix),
                  let source = Int(str.dropFirst(Self.panelMovePrefix.count)) else { return }
            Task { @MainActor in store.swapPanels(source, panelIndex) }
        }
        return true
    }

    /// 활성/비활성 모두 불투명 색을 써서 뒤 배경이 비쳐 생기는 "층" 현상을 방지.
    private var headerBackground: Color {
        guard showActiveIndicator else { return Palette.headerBackground }
        return isActive ? Palette.headerBackground : Palette.headerBackgroundInactive
    }

    private var divider: some View {
        Rectangle().fill(Palette.divider).frame(width: 1, height: 14)
    }

    /// 편집/미리보기 토글 + (편집 중일 때) 저장 버튼.
    private var editControls: some View {
        HStack(spacing: 1) {
            headerButton(
                help: loc.string(panel.isEditing ? .previewDocument : .editDocument),
                action: { store.toggleEditing(panel: panelIndex) }
            ) {
                Image(systemName: panel.isEditing ? "eye" : "pencil")
                    .font(.system(size: 12))
            }
            if panel.isEditing {
                headerButton(
                    help: loc.string(.saveDocument),
                    action: { store.save(panel: panelIndex) },
                    enabled: panel.isDirty
                ) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 12))
                }
            }
        }
    }

    /// 뷰어 본문 글자 크기 컨트롤.
    /// 단축키(⌘+/⌘-)는 포커스한 쪽을 키우지만, 이 버튼들은 뷰어를 누른 것이 분명하므로
    /// 트리에 포커스가 있어도 항상 본문에만 적용한다.
    private var fontControls: some View {
        HStack(spacing: 1) {
            headerButton(help: loc.string(.fontSmaller), action: store.decreaseViewerFont) {
                Image(systemName: "textformat.size.smaller").font(.system(size: 12))
            }
            headerButton(help: loc.string(.fontReset), action: store.resetViewerFont) {
                Text("\(Int(store.viewerFontSize))")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 20)
            }
            headerButton(help: loc.string(.fontLarger), action: store.increaseViewerFont) {
                Image(systemName: "textformat.size.larger").font(.system(size: 12))
            }
        }
    }

    /// 가운데 배율 라벨 문자열.
    /// - 이미지: 항상 % 표시(맞춤이면 실제 적용 배율, 명시 배율이면 그 값).
    /// - PDF: 명시 배율이면 %, 맞춤이면 "Fit".
    private var zoomLabel: String {
        if panel.pdfZoom > 0 {
            return "\(Int((panel.pdfZoom * 100).rounded()))%"
        }
        if panel.isImage {
            return "\(Int((panel.imageFitScale * 100).rounded()))%"
        }
        return loc.string(.zoomFit)
    }

    /// PDF·이미지 확대/축소 컨트롤. 가운데 라벨은 현재 배율이며 누르면 맞춤 복귀.
    private var pdfZoomControls: some View {
        HStack(spacing: 1) {
            headerButton(help: loc.string(.zoomOut), action: { store.pdfZoomOut(panel: panelIndex) }) {
                Image(systemName: "minus.magnifyingglass").font(.system(size: 12))
            }
            headerButton(help: loc.string(.zoomReset), action: { store.pdfZoomReset(panel: panelIndex) }) {
                Text(zoomLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 34)
            }
            headerButton(help: loc.string(.zoomIn), action: { store.pdfZoomIn(panel: panelIndex) }) {
                Image(systemName: "plus.magnifyingglass").font(.system(size: 12))
            }
        }
    }

    private var addPanelButton: some View {
        headerButton(help: loc.string(.addPanel), action: store.addPanel) {
            Image(systemName: "plus.rectangle").font(.system(size: 12))
        }
    }

    /// 터미널 패널 열기/닫기 토글. 켜져 있으면 아이콘을 강조 표시.
    private var terminalToggleButton: some View {
        Button(action: { store.toggleTerminal() }) {
            Image(systemName: store.showTerminal ? "terminal.fill" : "terminal")
                .font(.system(size: 12))
                .foregroundStyle(store.showTerminal ? Palette.accent : Palette.textMuted)
                .frame(height: 22)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(loc.string(.toggleTerminal))
    }

    /// Claude Code 실행 버튼. 터미널을 열고(또는 이미 열려 있으면) 셸에 `claude`를 입력한다.
    /// Claude 브랜드 로고(주황 배경 + 별 모양)를 원본 색으로 표시한다.
    private var claudeCodeButton: some View {
        Button(action: { store.launchClaudeCode() }) {
            Image("ClaudeIcon")
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 15, height: 15)
                .frame(height: 22)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(loc.string(.launchClaudeCode))
    }

    private var closeButton: some View {
        headerButton(help: loc.string(.closePanel), action: { store.removePanel(at: panelIndex) }) {
            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
        }
    }

    /// 헤더용 버튼. 라벨 주변 사각형 전체가 탭 영역.
    private func headerButton<Label: View>(
        help: String,
        action: @escaping () -> Void,
        enabled: Bool = true,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(enabled ? Palette.accent : Palette.textMuted)
                .frame(height: 22)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}
