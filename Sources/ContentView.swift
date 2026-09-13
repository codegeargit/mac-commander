import SwiftUI
import UniformTypeIdentifiers

/// Mac Commander 메인 화면.
/// 좌측 파일 트리 + 우측 마크다운 뷰어, 가운데 드래그로 폭 조절.
struct ContentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var loc: LocalizationManager
    @Environment(\.colorScheme) private var systemScheme
    /// ⌘+휠을 가로채는 로컬 이벤트 모니터(해제용 토큰).
    @State private var scrollMonitor: Any?

    /// 터미널을 붙여도 뷰어에 남겨 둘 최소 크기.
    private static let minViewerWidth: CGFloat = 320
    private static let minViewerHeight: CGFloat = 140

    var body: some View {
        VStack(spacing: 0) {
            // 열어둔 폴더가 없으면 창 전체를 시작 화면으로 쓴다. 트리 폭(좁은 칼럼)에
            // 안내를 밀어 넣으면 첫 실행에 무엇을 해야 하는지가 잘 읽히지 않는다.
            if let root = store.primaryPane.root {
                HStack(spacing: 0) {
                    FileTreeView(pane: store.primaryPane, root: root)
                        .frame(width: store.treeWidth)

                    // zIndex: 구분선의 히트 영역이 이웃 뷰(뷰어·터미널)에 덮이지 않게
                    // 형제 위로 올린다. 덮이면 그쪽 절반에서 커서가 바뀌지 않는다.
                    resizeDivider
                        .zIndex(1)

                    // 두 번째 트리(듀얼 모드). 필요할 때만 열고, 뷰어는 그 오른쪽에 그대로 둔다.
                    if store.isDualPane, let secondRoot = store.panes[1].root {
                        FileTreeView(pane: store.panes[1], root: secondRoot)
                            .frame(width: store.secondTreeWidth)
                        secondTreeDivider
                            .zIndex(1)
                    }

                    // 뷰어 패널들 + 터미널(오른쪽 또는 아래)
                    viewerArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)

                // 하단 상태바 — 커서 항목 정보 / 선택 요약 / 폴더 항목 수
                StatusBarView()

                // 트리가 둘일 때는 원작처럼 맨 아래에 F키 바를 둔다.
                // 반대편으로 복사·이동이 핵심 조작이 되므로 키를 눈앞에 보여 준다.
                if store.isDualPane {
                    FunctionKeyBar()
                }
            } else {
                WelcomeView()
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 440)
        .background(Palette.viewerBackground)
        // 이름 변경·파일 작업 오류. 트리가 둘이어도 한 번만 뜨도록 여기서 띄운다.
        .alert(loc.string(.renameTitle),
               isPresented: Binding(
                get: { store.renameError != nil },
                set: { if !$0 { store.renameError = nil } }
               )) {
            Button(loc.string(.ok), role: .cancel) { store.renameError = nil }
        } message: {
            Text(store.renameError ?? "")
        }
        // 삭제 확인.
        .alert(loc.string(.deleteTitle),
               isPresented: Binding(
                get: { !store.pendingDeleteURLs.isEmpty },
                set: { if !$0 { store.cancelDelete() } }
               )) {
            Button(loc.string(.cancel), role: .cancel) { store.cancelDelete() }
            Button(loc.string(.moveToTrash), role: .destructive) { store.confirmDelete() }
        } message: {
            // 단일이면 파일명, 다중이면 "N개 항목을 휴지통으로?".
            if store.pendingDeleteCount == 1 {
                Text(loc.string(.confirmDelete(store.pendingDeleteName)))
            } else {
                Text(loc.string(.confirmDeleteMulti(store.pendingDeleteCount)))
            }
        }
        // 반대편 트리로 복사·이동 확인(듀얼 모드 F5·F6).
        .sheet(item: $store.pendingTransfer) { request in
            TransferView(request: request)
                .environmentObject(store)
                .environmentObject(loc)
        }
        // 멀티 리네임 시트 (Total Commander MRT)
        .sheet(isPresented: $store.showMultiRename) {
            MultiRenameView()
                .environmentObject(store)
                .environmentObject(theme)
                .environmentObject(loc)
        }
        // 키보드 단축키 도움말 시트
        .sheet(isPresented: $store.showShortcuts) {
            ShortcutsView()
                .environmentObject(loc)
        }
        // 지원 파일 형식 도움말 시트
        .sheet(isPresented: $store.showFileTypes) {
            FileTypesView()
                .environmentObject(loc)
        }
        // 오픈소스 고지 시트
        .sheet(isPresented: $store.showAcknowledgements) {
            AcknowledgementsView()
                .environmentObject(loc)
        }
        // 폴더로 이동(⌘⇧G) 시트 — 현재 루트 경로로 초기화.
        .sheet(isPresented: $store.showGoToFolder) {
            GoToFolderView(initialPath: store.root?.url.path ?? "")
                .environmentObject(store)
                .environmentObject(loc)
        }
        // 파일명으로 문서 찾아 열기(⌘P).
        .sheet(isPresented: $store.showQuickOpen) {
            QuickOpenView(index: store.fileIndex)
                .environmentObject(store)
                .environmentObject(loc)
        }
        // 폴더 전체 본문 검색(⇧⌘F).
        .sheet(isPresented: $store.showContentSearch) {
            ContentSearchView(index: store.fileIndex, search: store.contentSearch)
                .environmentObject(store)
                .environmentObject(loc)
        }
        // 창 전체에 폴더 드래그앤드롭 지원
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        // 시스템 다크/라이트 변화를 ThemeManager에 반영(‘시스템’ 테마용).
        .onAppear {
            theme.systemIsDark = (systemScheme == .dark)
            installScrollMonitor()
        }
        .onDisappear { removeScrollMonitor() }
        .onChange(of: systemScheme) { _, new in theme.systemIsDark = (new == .dark) }
    }

    /// 뷰어 패널들과 터미널을 함께 배치한다. 터미널은 오른쪽(세로) 또는 아래(가로)에 붙는다.
    ///
    /// 위치 전환을 `if/else` 분기로 만들면 SwiftUI가 두 배치를 **서로 다른 뷰**로 보고
    /// 터미널을 새로 만들어 버린다. 그러면 실행 중이던 셸이 죽어서 돌리던 작업(claude 세션
    /// 같은 것)이 날아간다. 그래서 터미널을 계층상 같은 자리에 두고 프레임과 오프셋만 바꾼다.
    private var viewerArea: some View {
        GeometryReader { geo in
            let atBottom = store.terminalPosition == .bottom
            let visible = store.showTerminal
            // 구분선 1pt를 빼고 남는 자리를 나눈다. 뷰어가 뭉개지지 않게 상한을 둔다.
            let gap: CGFloat = visible ? 1 : 0
            let termWidth = visible && !atBottom
                ? min(store.terminalWidth, max(geo.size.width - Self.minViewerWidth - gap, 0))
                : 0
            let termHeight = visible && atBottom
                ? min(store.terminalHeight, max(geo.size.height - Self.minViewerHeight - gap, 0))
                : 0
            let viewerWidth = max(geo.size.width - termWidth - (atBottom ? 0 : gap), 1)
            let viewerHeight = max(geo.size.height - termHeight - (atBottom ? gap : 0), 1)

            ZStack(alignment: .topLeading) {
                viewerPanels
                    .frame(width: viewerWidth, height: viewerHeight)

                if visible {
                    // 구분선은 방향이 다르므로 분기해도 된다(커서 핸들뿐이라 다시 만들어도 무해).
                    Group {
                        if atBottom {
                            ResizeDivider(axis: .vertical) { delta in
                                // 구분선을 아래로(+) 끌면 터미널이 낮아진다.
                                store.setTerminalHeight(store.terminalHeight - delta,
                                                        limit: geo.size.height - Self.minViewerHeight - gap)
                            }
                            .frame(width: geo.size.width, height: 1)
                            .offset(y: viewerHeight)
                        } else {
                            ResizeDivider { delta in
                                // 구분선을 오른쪽으로(+) 끌면 터미널이 좁아진다.
                                store.setTerminalWidth(store.terminalWidth - delta,
                                                       limit: geo.size.width - Self.minViewerWidth - gap)
                            }
                            .frame(width: 1, height: geo.size.height)
                            .offset(x: viewerWidth)
                        }
                    }
                    .zIndex(1)

                    TerminalPanel()
                        .frame(width: atBottom ? geo.size.width : termWidth,
                               height: atBottom ? termHeight : geo.size.height)
                        .offset(x: atBottom ? 0 : viewerWidth + gap,
                                y: atBottom ? viewerHeight + gap : 0)
                }
            }
        }
    }

    /// 우측 패널들을 가로로 나란히 배치. 패널 사이 구분선은 드래그로 폭 조절.
    private var viewerPanels: some View {
        GeometryReader { geo in
            let weights = store.panelWeights
            let sum = max(weights.reduce(0, +), 0.0001)
            // 구분선 폭(1pt * (n-1))을 제외한 실제 콘텐츠 폭.
            let dividerTotal = CGFloat(max(store.panels.count - 1, 0))
            let contentWidth = max(geo.size.width - dividerTotal, 1)

            HStack(spacing: 0) {
                ForEach(Array(store.panels.enumerated()), id: \.element.id) { index, panel in
                    if index > 0 {
                        panelDivider(leftIndex: index - 1, totalWidth: contentWidth)
                            .zIndex(1)
                    }
                    DocumentDetailView(
                        panel: panel,
                        panelIndex: index,
                        isActive: index == store.activePanelIndex,
                        showActiveIndicator: store.panels.count > 1
                    )
                    .frame(width: width(at: index, weights: weights, sum: sum, content: contentWidth))
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { store.activatePanel(index) }
                }
            }
        }
    }

    /// 가중치 기준 패널 폭. 마지막 패널은 잔여폭을 받아 반올림 오차를 흡수.
    private func width(at index: Int, weights: [CGFloat], sum: CGFloat, content: CGFloat) -> CGFloat {
        guard weights.indices.contains(index) else { return content }
        if index == weights.count - 1 {
            let others = weights[0..<index].reduce(0) { $0 + ($1 / sum * content) }
            return max(content - others, 1)
        }
        return weights[index] / sum * content
    }

    /// 두 패널 사이 드래그 가능한 구분선.
    private func panelDivider(leftIndex: Int, totalWidth: CGFloat) -> some View {
        ResizeDivider { delta in
            store.resizePanel(divider: leftIndex, by: delta, totalWidth: totalWidth)
        }
    }

    /// 기본 트리 오른쪽의 드래그 가능한 구분선.
    private var resizeDivider: some View {
        ResizeDivider { delta in
            store.setTreeWidth(store.treeWidth + delta)
        }
    }

    /// 두 번째 트리와 뷰어 사이의 드래그 가능한 구분선.
    private var secondTreeDivider: some View {
        ResizeDivider { delta in
            store.setSecondTreeWidth(store.secondTreeWidth + delta)
        }
    }

    /// ⌘+휠로 **마우스가 놓인 영역**의 글자 크기를 조절한다.
    ///
    /// SwiftUI에는 스크롤 휠 훅이 없고, 트리·터미널·웹뷰는 각자 자기 AppKit 뷰에서 휠을
    /// 먼저 가로챈다. 그래서 앱 이벤트 큐에서 먼저 낚아채는 로컬 모니터를 쓴다
    /// (PDF 확대가 이미 같은 방식이다).
    ///
    /// PDF·이미지 패널 위에서는 스토어가 false를 돌려주므로 이벤트를 그대로 흘려보내
    /// 그쪽의 배율 로직이 처리하게 둔다.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        let store = self.store   // 뷰 struct 대신 스토어 참조만 캡처
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
            guard delta != 0 else { return event }
            guard store.zoomHoveredArea(scrollingUp: delta > 0) else { return event }
            return nil   // 처리했으므로 이벤트를 소비한다(기본 스크롤 방지).
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    /// 드롭된 첫 번째 폴더를 워크스페이스로 연다.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            guard isDir.boolValue else { return }
            Task { @MainActor in store.openFolder(url) }
        }
        return true
    }
}

