import SwiftUI

/// 좌측 파일 트리 패널 (레트로 Commander 스타일). 키보드 탐색 지원.
struct FileTreeView: View {
    @ObservedObject var root: FileNode
    let rootPath: String
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var theme: ThemeManager
    @FocusState private var isFocused: Bool
    /// 현재 드롭 하이라이트 대상 폴더 URL.
    @State private var dropTargetURL: URL?
    /// 다음 커서 변경에 자동 스크롤을 붙이지 않는다(마우스 클릭 직후).
    @State private var suppressCursorScroll = false

    private var hasTreeFocus: Bool { store.focus == .tree }

    /// 드롭 대상 노드가 실제로 받게 될 폴더 URL(폴더면 자신, 파일이면 부모).
    private func dropFolder(for node: FileNode) -> URL {
        node.isDirectory ? node.url : node.url.deletingLastPathComponent()
    }

    /// 드롭 처리: Option(⌥) 누른 상태면 복사, 아니면 이동.
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
                Button(action: { store.goToParentOrPrompt() }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(store.canGoToParent ? Palette.accent : Palette.textMuted)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!store.canGoToParent)
                .help(loc.string(.goToParentTooltip))

                Image(systemName: "folder.fill")
                    .foregroundStyle(Palette.accent)
                Text(rootPath)
                    .font(.system(size: store.treeFontSize, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 6)

                // 정렬 기준 메뉴
                sortMenu

                // 파일 필터 세그먼트 토글: [MD] | [전체]
                fileFilterToggle
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
                        ForEach(store.visibleNodes) { node in
                            FileTreeRow(
                                node: node,
                                depth: depth(of: node),
                                isExpanded: store.isExpanded(node),
                                isSelected: store.selectedURL == node.url,
                                isCursor: store.cursorURL == node.url,
                                isMarked: store.isMarked(node.url),
                                treeHasFocus: hasTreeFocus,
                                isRenaming: store.renamingURL == node.url,
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
                                store.focus = .tree
                                isFocused = true
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
                                    Button(loc.string(.enterFolder)) { store.enterFolder(node) }
                                    Divider()
                                }
                                Button(loc.string(.newMarkdownFile)) { store.createMarkdownFile(near: node) }
                                Button(loc.string(.newFolder)) { store.createFolder(near: node) }
                                Divider()
                                Button(loc.string(.openInTerminal)) { store.openInTerminal(near: node) }
                                Divider()
                                Button(loc.string(.copyPath)) { store.copyPath(node.url) }
                                Button(loc.string(.copyRelativePath)) { store.copyRelativePath(node.url) }
                                Divider()
                                Button(loc.string(.rename)) { store.beginRename(node) }
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
                .onChange(of: store.cursorURL) { _, url in
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
                Button(loc.string(.newMarkdownFile)) { store.createMarkdownFile(near: nil) }
                Button(loc.string(.newFolder)) { store.createFolder(near: nil) }
                Divider()
                Button(loc.string(.openInTerminal)) { store.openInTerminal(near: nil) }
            }
        }
        // ⌘+휠 확대 대상을 정하기 위해 마우스가 트리에 있음을 알린다.
        .onHover { inside in
            if inside { store.hoverArea = .tree }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onChange(of: store.focus) { _, newValue in
            isFocused = (newValue == .tree)
        }
        .onKeyPress { press in handleKey(press) }
        .alert(loc.string(.renameTitle),
               isPresented: Binding(
                get: { store.renameError != nil },
                set: { if !$0 { store.renameError = nil } }
               )) {
            Button(loc.string(.ok), role: .cancel) { store.renameError = nil }
        } message: {
            Text(store.renameError ?? "")
        }
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
            if store.markedCount > 0 { store.clearMarks(); return .handled }
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
                    .strokeBorder(Palette.accent.opacity(treeHasFocus ? 0.9 : 0.4), lineWidth: 1)
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
