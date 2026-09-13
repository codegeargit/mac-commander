import SwiftUI

/// 파일 트리 패널 (레트로 Commander 스타일). 키보드 탐색 지원.
///
/// 듀얼 모드에서는 트리 둘이 나란히 뜬다. 각 트리는 자기 `TreePane` 상태를 그리고,
/// 클릭·키 입력이 들어오면 먼저 자기를 활성 트리로 만든 뒤 스토어 동작을 부른다
/// (스토어의 트리 동작은 활성 트리를 대상으로 한다).
struct FileTreeView: View {
    @ObservedObject var pane: TreePane
    @ObservedObject var root: FileNode
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var theme: ThemeManager
    @FocusState private var isFocused: Bool
    /// 현재 드롭 하이라이트 대상 폴더 URL.
    @State private var dropTargetURL: URL?
    /// 다음 커서 변경에 자동 스크롤을 붙이지 않는다(마우스 클릭 직후).
    @State private var suppressCursorScroll = false

    /// 이 트리가 키 입력을 받는 중인지.
    private var hasTreeFocus: Bool { store.isActivePane(pane) }
    /// 이 트리가 두 번째(듀얼 모드용) 트리인지.
    private var isSecondPane: Bool { store.panes.last === pane }

    /// 이 트리를 활성으로 만든다. 모든 사용자 동작의 첫 단계.
    private func activate() {
        store.activatePane(pane)
        isFocused = true
    }

    /// 드롭 대상 노드가 실제로 받게 될 폴더 URL(폴더면 자신, 파일이면 부모).
    private func dropFolder(for node: FileNode) -> URL {
        node.isDirectory ? node.url : node.url.deletingLastPathComponent()
    }

    /// 드롭 처리: Option(⌥) 누른 상태면 복사, 아니면 이동.
    /// 다른 트리에서 끌어온 항목도 URL로 오므로 두 트리 사이 끌어 놓기가 그대로 된다.
    private func handleDrop(_ items: [URL], onto node: FileNode) -> Bool {
        let destDir = dropFolder(for: node)
        let copy = NSEvent.modifierFlags.contains(.option)
        var any = false
        for source in items {
            if store.dropItem(source, into: destDir, copy: copy) { any = true }
        }
        return any
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더 바 (상위 이동 버튼 + 현재 경로)
            HStack(spacing: 4) {
                Button(action: { activate(); store.goToParentOrPrompt() }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(pane.canGoToParent ? Palette.accent : Palette.textMuted)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!pane.canGoToParent)
                .help(loc.string(.goToParentTooltip))

                Image(systemName: "folder.fill")
                    .foregroundStyle(Palette.accent)
                Text(root.url.path)
                    .font(.system(size: store.treeFontSize, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 6)

                // 정렬 기준 메뉴
                sortMenu

                // 파일 필터 세그먼트 토글: [MD] | [전체]
                fileFilterToggle

                // 두 번째 트리 열기/닫기(⇧⌘D). 기본 트리에는 열기 토글, 두 번째 트리에는 닫기.
                dualPaneButton
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Palette.headerBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(hasTreeFocus ? Palette.accent : Palette.divider)
                    .frame(height: hasTreeFocus ? 2 : 1)
            }

            // 트리 본문
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(pane.visibleNodes) { node in
                            FileTreeRow(
                                node: node,
                                depth: depth(of: node),
                                isExpanded: pane.expandedURLs.contains(node.url),
                                // 뷰어에 열린 파일 강조는 그 파일을 연 트리에만 칠한다.
                                isSelected: store.selectedURL == node.url && store.highlightsOpenFile(in: pane),
                                // 듀얼 모드에서는 비활성 트리의 커서도 F5·F6의 보낼 항목이나 받을 폴더가
                                // 되므로 알아볼 수 있게 남긴다.
                                isInactivePane: store.isDualPane && store.activePane !== pane,
                                isCursor: pane.cursorURL == node.url,
                                isMarked: pane.markedURLs.contains(node.url),
                                treeHasFocus: hasTreeFocus,
                                // 같은 파일이 두 트리에 다 보여도 편집 칸은 작업 중인 트리에만 뜬다.
                                isRenaming: store.renamingURL == node.url && store.activePane === pane,
                                isDropTarget: dropTargetURL != nil && dropTargetURL == dropFolder(for: node)
                            )
                            .id(node.url)
                            // 탭 제스처는 하나만 둔다: .onTapGesture(count: 2)를 따로 붙이면
                            // 단일 클릭이 더블클릭 판정 대기(시스템 더블클릭 간격)만큼 지연된다.
                            // 대신 NSApp.currentEvent의 clickCount로 구분해, 첫 클릭은 즉시
                            // 단일클릭 동작을 실행하고 두 번째 클릭에서 더블클릭 동작을 실행한다.
                            .onTapGesture {
                                guard store.renamingURL == nil else { return }
                                // 클릭한 행은 이미 화면에 있으므로 뒤따르는 커서 변경에
                                // 스크롤이 붙지 않게 한다.
                                suppressCursorScroll = true
                                activate()
                                // 더블클릭: 폴더면 그 폴더로 진입(새 루트). 파일이면 열기.
                                if NSApp.currentEvent?.clickCount == 2 {
                                    if node.isDirectory {
                                        store.enterFolder(node)
                                    } else {
                                        store.select(node)
                                    }
                                    return
                                }
                                let mods = NSEvent.modifierFlags
                                if mods.contains(.command) {
                                    // Cmd+클릭: 파일이면 새 뷰어 패널에 열기(폴더는 무시).
                                    store.cursorURL = node.url
                                    if !node.isDirectory { store.openInNewPanel(node.url) }
                                } else if mods.contains(.option) {
                                    // Option+클릭: 이 항목만 선택 토글(다중 선택).
                                    store.toggleMark(node.url)
                                } else if mods.contains(.shift) {
                                    // Shift+클릭: 커서부터 이 항목까지 범위 선택.
                                    store.markRange(to: node.url)
                                } else {
                                    // 일반 클릭: 단일 선택 의도 → 다중 선택 해제.
                                    store.clearMarks()
                                    // 폴더든 파일이든 커서를 옮긴다(폴더도 클릭으로 선택되게).
                                    // select()는 폴더면 커서만 옮기고 뷰어는 건드리지 않는다.
                                    store.select(node)
                                    if node.isDirectory { store.toggleExpand(node) }
                                }
                            }
                            .contextMenu {
                                if node.isDirectory {
                                    Button(loc.string(.enterFolder)) { activate(); store.enterFolder(node) }
                                    Divider()
                                }
                                Button(loc.string(.newMarkdownFile)) { activate(); store.createMarkdownFile(near: node) }
                                Button(loc.string(.newFolder)) { activate(); store.createFolder(near: node) }
                                Divider()
                                Button(loc.string(.openInTerminal)) { store.openInTerminal(near: node) }
                                Divider()
                                Button(loc.string(.copyPath)) { store.copyPath(node.url) }
                                Button(loc.string(.copyRelativePath)) { activate(); store.copyRelativePath(node.url) }
                                Divider()
                                Button(loc.string(.rename)) { activate(); store.beginRename(node) }
                                Button(loc.string(.delete), role: .destructive) { store.requestDelete(node) }
                            }
                            // 드래그 소스: 이 노드의 URL을 페이로드로.
                            .draggable(node.url) {
                                Label(node.name, systemImage: node.isDirectory ? "folder.fill" : "doc.text")
                                    .padding(4)
                            }
                            // 드롭 타깃: 폴더면 그 폴더로, 파일이면 그 부모 폴더로 이동/복사.
                            .dropDestination(for: URL.self) { items, _ in
                                handleDrop(items, onto: node)
                            } isTargeted: { hovering in
                                dropTargetURL = hovering ? dropFolder(for: node) : nil
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, minHeight: 0, alignment: .topLeading)
                }
                // 커서가 화면 밖으로 나갔을 때만 따라간다.
                //
                // anchor를 주면 커서가 이미 보이는 경우에도 그 위치(가운데)로 목록을
                // 끌어당겨, 한 칸 움직이거나 폴더를 펼칠 때마다 트리 전체가 흔들린다.
                // nil이면 커서를 보이게 하는 데 필요한 최소량만 스크롤한다.
                .onChange(of: pane.cursorURL) { _, url in
                    // 마우스로 고른 행은 이미 눈앞에 있다. 클릭에는 스크롤하지 않는다
                    // (폴더를 펼칠 때 목록이 제자리에 있고 아래로만 늘어나게).
                    guard !suppressCursorScroll else {
                        suppressCursorScroll = false
                        return
                    }
                    if let url {
                        withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(url) }
                    }
                }
            }
            .background(Palette.panelBackground)
            // 빈 영역 우클릭 → 루트에 새 항목 생성.
            .contextMenu {
                Button(loc.string(.newMarkdownFile)) { activate(); store.createMarkdownFile(near: nil) }
                Button(loc.string(.newFolder)) { activate(); store.createFolder(near: nil) }
                Divider()
                Button(loc.string(.openInTerminal)) { activate(); store.openInTerminal(near: nil) }
            }
        }
        // ⌘+휠 확대 대상을 정하기 위해 마우스가 트리에 있음을 알린다.
        .onHover { inside in
            if inside { store.hoverArea = .tree }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        // 키보드 포커스는 활성 트리 하나만 잡는다. 둘 다 잡으려 하면 서로 뺏으며 깜빡인다.
        .onAppear { if hasTreeFocus { isFocused = true } }
        .onChange(of: store.focus) { _, _ in isFocused = hasTreeFocus }
        .onChange(of: store.activePaneIndex) { _, _ in isFocused = hasTreeFocus }
        .onKeyPress { press in handleKey(press) }
        // 이름 변경 오류·삭제 확인 창은 트리가 둘이어도 한 번만 떠야 하므로 ContentView가 띄운다.
    }

    /// 헤더의 두 번째 트리 버튼. 기본 트리에서는 열기/닫기 토글, 두 번째 트리에서는 닫기.
    @ViewBuilder
    private var dualPaneButton: some View {
        if isSecondPane && store.isDualPane {
            Button(action: { store.closeSecondPane() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(loc.string(.menuCloseSecondTree)) (⇧⌘D)")
        } else if !isSecondPane {
            Button(action: { store.toggleDualPane() }) {
                Image(systemName: store.isDualPane ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(loc.string(store.isDualPane ? .menuCloseSecondTree : .menuOpenSecondTree)) (⇧⌘D)")
        }
    }

    /// 정렬 기준 메뉴. 같은 기준을 다시 고르면 방향이 뒤집힌다.
    private var sortMenu: some View {
        Menu {
            SortMenuItems()
                .environmentObject(store)
                .environmentObject(loc)
        } label: {
            Image(systemName: store.sortOrder.ascending
                  ? "arrow.up.arrow.down" : "arrow.down.arrow.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.accent)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(loc.string(.sortMenu))
    }

    /// 파일 필터 세그먼트 토글: [MD] | [전체]. 직관적으로 현재 모드를 강조한다.
    private var fileFilterToggle: some View {
        HStack(spacing: 0) {
            segment(title: "MD", active: !store.showAllFiles) {
                store.showAllFiles = false
            }
            segment(title: "ALL", active: store.showAllFiles) {
                store.showAllFiles = true
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Palette.divider, lineWidth: 1)
        )
        .help(loc.string(store.showAllFiles ? .filterAllFiles : .filterMarkdownOnly))
    }

    private func segment(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(active ? Palette.selectForeground : Palette.textMuted)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(active ? Palette.accent : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 노드의 트리 깊이(루트 기준)를 경로 컴포넌트 수 차이로 계산.
    private func depth(of node: FileNode) -> Int {
        node.url.pathComponents.count - root.url.pathComponents.count - 1
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // 이름 편집 중에는 트리 키 탐색을 막는다(TextField가 입력을 받음).
        guard hasTreeFocus, store.renamingURL == nil else { return .ignored }
        // 키보드로 움직일 때는 커서가 화면 밖으로 나갈 수 있으므로 스크롤이 따라와야 한다.
        // (직전 클릭이 커서를 옮기지 않았다면 억제 플래그가 남아 있을 수 있다.)
        suppressCursorScroll = false
        switch press.key {
        case .upArrow:    store.moveCursor(by: -1); return .handled
        case .downArrow:  store.moveCursor(by: 1);  return .handled
        case .rightArrow: store.expandOrEnter();    return .handled
        case .leftArrow:  store.collapseOrParent(); return .handled
        case .return:     store.activateCursor();   return .handled
        // 다중 선택(Total Commander): Space=토글, Insert=토글 후 아래로.
        case .space:                       store.toggleMarkAtCursor();   return .handled
        case KeyEquivalent("\u{F746}"):    store.toggleMarkAndAdvance();  return .handled // Insert
        // Escape: 다중 선택 전체 해제(선택이 있을 때만 소비).
        case .escape:
            if !pane.markedURLs.isEmpty { store.clearMarks(); return .handled }
            return .ignored
        default:          return .ignored
        }
    }
}

/// 정렬 메뉴의 항목들. 트리 헤더 메뉴와 메뉴바(보기)에서 같은 것을 쓴다.
struct SortMenuItems: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
        // 현재 기준에 체크를 붙인다. 같은 항목을 다시 누르면 방향이 뒤집힌다.
        ForEach(SortField.allCases) { field in
            Button(action: { store.setSortField(field) }) {
                if store.sortOrder.field == field {
                    Label(loc.string(label(for: field)),
                          systemImage: store.sortOrder.ascending ? "chevron.up" : "chevron.down")
                } else {
                    Text(loc.string(label(for: field)))
                }
            }
        }
        Divider()
        Button(loc.string(store.sortOrder.ascending ? .sortDescending : .sortAscending)) {
            store.toggleSortDirection()
        }
    }

    private func label(for field: SortField) -> L10n {
        switch field {
        case .name:     return .sortByName
        case .modified: return .sortByModified
        case .size:     return .sortBySize
        }
    }
}

/// 트리의 한 행.
private struct FileTreeRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var theme: ThemeManager
    let node: FileNode
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    /// 듀얼 모드에서 활성이 아닌 트리의 행인지.
    let isInactivePane: Bool
    let isCursor: Bool
    let isMarked: Bool
    let treeHasFocus: Bool
    let isRenaming: Bool
    let isDropTarget: Bool

    @State private var draftName: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            // 다중 선택 마커(좌측 시안 바). 선택되지 않은 행은 자리만 차지.
            Rectangle()
                .fill(isMarked ? Palette.accent : Color.clear)
                .frame(width: 2.5)

            Spacer().frame(width: CGFloat(depth) * store.treeIndentWidth)

            if node.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: store.treeFontSize * 0.72))
                    .foregroundStyle(isSelected ? Palette.selectForeground : Palette.textMuted)
                    .frame(width: store.treeFontSize * 0.8)
            } else {
                Spacer().frame(width: store.treeFontSize * 0.8)
            }

            Image(systemName: iconName)
                .font(.system(size: store.treeFontSize * 0.88))
                .foregroundStyle(iconColor)

            if isRenaming {
                TextField("", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: store.treeFontSize, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .focused($fieldFocused)
                    .onSubmit { store.commitRename(node, to: draftName) }
                    .onExitCommand { store.cancelRename() }
                    .onAppear {
                        draftName = node.name
                        beginEditingFocus()
                    }
                    .onChange(of: fieldFocused) { _, focused in
                        // 포커스를 잃으면(다른 곳 클릭) 변경 확정.
                        if !focused, store.renamingURL == node.url {
                            store.commitRename(node, to: draftName)
                        }
                    }
            } else {
                Text(node.name)
                    .font(.system(size: store.treeFontSize, weight: textWeight, design: .monospaced))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: store.treeRowHeight)
        .background(rowBackground)
        .overlay {
            if isDropTarget {
                // 드롭 대상 폴더 강조.
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Palette.accent, lineWidth: 1.5)
            } else if isCursor && !isSelected {
                // 키보드 커서 표시(선택과 별개).
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Palette.accent.opacity(treeHasFocus ? 0.9 : isInactivePane ? 0.7 : 0.4),
                                  lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }

    /// 인라인 편집 시작 시 포커스를 확실히 잡고, 편집 필드의 텍스트를 전체 선택한다.
    ///
    /// 새 폴더/파일 생성 직후 이 행은 리스트 diff로 갓 mount되므로 .onAppear에서
    /// 곧바로 focus를 요청하면 뷰가 window에 붙기 전이라 무시될 수 있다.
    /// 다음 runloop로 한 틱 미뤄 안정적으로 포커스를 잡는다.
    /// 이어서 NSTextView의 텍스트를 전체 선택해 바로 입력하면 기존 이름이 대체되게 한다.
    private func beginEditingFocus() {
        DispatchQueue.main.async {
            fieldFocused = true
            // 포커스가 첫 응답자로 반영된 다음 틱에 텍스트를 전체 선택한다.
            DispatchQueue.main.async {
                if let editor = NSApp.keyWindow?.firstResponder as? NSText {
                    editor.selectAll(nil)
                }
            }
        }
    }

    private var rowBackground: Color {
        if isDropTarget { return Palette.accent.opacity(0.2) }
        if isSelected { return Palette.selectBackground }
        if isMarked { return Palette.accent.opacity(0.12) }   // 다중 선택 강조
        if isCursor && treeHasFocus { return Palette.accent.opacity(0.15) }
        if isCursor && isInactivePane { return Palette.accent.opacity(0.08) }
        return .clear
    }

    /// 폴더 / 마크다운 / PDF / 서식 문서 / 일반 파일에 따른 아이콘.
    private var iconName: String {
        if node.isDirectory { return "folder.fill" }
        if node.isPDF { return "doc.richtext" }
        if node.isRichDoc { return "doc.plaintext" }
        return node.isMarkdown ? "doc.text" : "doc"
    }

    private var iconColor: Color {
        if isSelected { return Palette.selectForeground }
        if node.isDirectory { return Palette.textFolder }
        // 뷰어가 여는 파일(마크다운·PDF)은 강조, 그 외는 흐리게.
        return node.isViewable ? Palette.accentDim : Palette.textMuted
    }

    private var textColor: Color {
        if isSelected { return Palette.selectForeground }
        if isMarked { return Palette.accent }   // 선택 항목은 강조색(TC 느낌)
        if node.isDirectory { return Palette.textFolder }
        return node.isViewable ? Palette.textPrimary : Palette.textMuted // 비-뷰어 파일은 흐리게
    }

    /// 선택(marked)된 항목은 굵게 표시.
    private var textWeight: Font.Weight { isMarked ? .bold : .regular }
}
