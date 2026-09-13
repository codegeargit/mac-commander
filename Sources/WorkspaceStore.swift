import SwiftUI

/// 뷰어에 내려보내는 문서 내 검색 요청.
///
/// 뷰어는 종류마다 검색 수단이 다르다(웹뷰는 `WKWebView.find`, PDF는 `PDFDocument.findString`).
/// 스토어는 "무엇을 어느 방향으로 찾아라"만 정하고, 실제 검색은 각 뷰가 맡는다.
struct FindRequest: Equatable {
    var query: String
    /// 아래(다음) 방향으로 찾을지. false면 위로.
    var forward: Bool
    /// 입력이 바뀌어 새로 찾는 경우(증분 검색)인지. false면 "다음/이전 찾기".
    /// 증분 검색은 지금 있는 자리에서 다시 찾아야 한다. 다음 결과로 넘어가 버리면
    /// 한 글자 칠 때마다 문서가 앞으로 밀린다.
    var isNewSearch: Bool
    /// 같은 문자열로 "다음 찾기"를 반복해도 새 요청임을 알 수 있게 하는 일련번호.
    /// 이게 없으면 값이 같아 뷰가 변화를 감지하지 못한다.
    var sequence: Int
}

/// 최근에 열었던 폴더 하나.
///
/// 경로는 목록에 보여주는 용도, 북마크는 다시 열 때 접근 권한을 되살리는 용도다.
/// 북마크 생성이 실패할 수 있어(권한 없는 위치 등) 옵셔널로 둔다.
struct RecentFolder: Codable, Identifiable, Equatable {
    var path: String
    var bookmark: Data?

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

/// 우측 뷰어 패널 하나. 열린 파일과 그 본문을 담는다.
struct ViewerPanel: Identifiable {
    let id = UUID()
    var fileURL: URL?
    /// 디스크에 저장된 본문(렌더링 및 dirty 판정의 기준).
    var content: String?
    /// 편집 모드 여부. true면 TextEditor, false면 마크다운 렌더링.
    var isEditing: Bool = false
    /// 편집 중인 본문(편집 모드에서만 의미). 저장 시 content로 반영.
    var draft: String = ""

    /// 마크다운이 아닌 파일을 열었는지 — true면 렌더링 대신 평문으로 표시.
    var isPlainText: Bool = false

    /// PDF 파일을 열었는지 — true면 PDFKit 뷰로 표시(content/편집 미사용).
    var isPDF: Bool = false

    /// 이미지 파일을 열었는지 — true면 ImageViewer로 표시(content/편집 미사용).
    var isImage: Bool = false

    /// HTML 파일을 열었는지 — true면 WebView로 파일을 그대로 렌더링.
    /// content에는 원문(태그 포함)을 담아 편집 모드(⌘E)에서 소스를 볼 수 있게 한다.
    var isHTML: Bool = false

    /// Word·Office·iWork 문서를 열었는지 — true면 QuickLook으로 표시.
    /// 이진(또는 압축) 포맷이라 content/편집은 쓰지 않는다.
    var isRichDoc: Bool = false

    /// 서식 문서를 LibreOffice로 변환해 둔 PDF(있으면 QuickLook 대신 이걸 보여준다).
    /// QuickLook이 표 폭을 무시하는 문제를 피하려는 경로라, 변환 전에는 nil이다.
    var richDocPDF: URL?

    /// 변환이 진행 중인지(헤더에 표시). 완료되면 richDocPDF가 채워진다.
    var isConverting: Bool = false

    /// 변환본이 있어도 QuickLook으로 보겠다고 고른 상태인지(헤더 버튼으로 전환).
    var prefersQuickLook: Bool = false

    /// 변환된 PDF로 보고 있는 상태인지.
    var isConvertedPDF: Bool { isRichDoc && richDocPDF != nil && !prefersQuickLook }

    /// PDFKit 뷰로 그리는 중인지(원본 PDF 또는 변환된 서식 문서).
    /// 확대/축소·찾기가 걸리는 범위를 이 값으로 통일한다.
    var showsPDF: Bool { isPDF || isConvertedPDF }

    /// PDF·이미지 확대 배율. 0이면 "맞춤(autoScale)" 모드, >0이면 명시적 배율.
    /// 사용자가 확대/축소를 누르면 명시적 배율로 전환된다.
    var pdfZoom: CGFloat = 0

    /// PDF 뷰어가 보여 주는 현재 쪽과 전체 쪽수(헤더 표시용). 0이면 아직 모름.
    var pdfPage: Int = 0
    var pdfPageCount: Int = 0

    /// 이미지 맞춤 모드에서 뷰가 실제로 적용 중인 배율(헤더 % 표시용).
    /// 뷰 크기에 따라 계산되어 뷰가 알려준다. pdfZoom > 0이면 의미 없음.
    var imageFitScale: CGFloat = 1

    /// 문서 내 찾기 바 표시 여부.
    var showFind: Bool = false
    /// 찾기 입력 문자열.
    var findQuery: String = ""
    /// 뷰어가 실행할 검색 요청(없으면 대기 상태).
    var findRequest: FindRequest?
    /// 마지막 검색에서 결과를 찾지 못했는지(입력 필드 강조용).
    var findMissed: Bool = false

    var fileName: String? { fileURL?.lastPathComponent }

    /// 편집 본문이 저장된 본문과 달라 저장이 필요한 상태인지.
    var isDirty: Bool { isEditing && draft != (content ?? "") }

    /// 이 패널의 현재 뷰어가 문서 내 찾기를 지원하는지.
    /// 마크다운·HTML(웹뷰), 평문(NSTextView), PDF(PDFKit)는 각자 검색 수단이 있다.
    /// 이미지와 편집 모드는 없다. 서식 문서는 QuickLook으로 보는 동안에는 찾기를 걸 수 없고
    /// (QuickLook 자체 검색을 쓴다), PDF로 변환되고 나면 PDFKit 검색이 살아난다.
    var supportsFind: Bool {
        guard fileURL != nil, !isEditing, !isImage else { return false }
        if isRichDoc { return isConvertedPDF }
        return isPDF || content != nil
    }
}

/// 앱의 작업 상태(루트 폴더, 트리, 뷰어 패널들)와 세션 영속화를 담당.
@MainActor
final class WorkspaceStore: ObservableObject {
    /// 루트 폴더 노드(없으면 폴더 미선택 상태).
    @Published var root: FileNode? {
        didSet {
            guard oldValue?.url != root?.url else { return }
            startWatchingRoot()
        }
    }

    /// 루트 하위 트리의 외부(Finder 등) 변경을 감시해 트리를 자동 갱신한다.
    private var directoryWatcher: DirectoryWatcher?

    /// 우측 뷰어 패널들(1~maxPanels). 가로로 나란히 표시.
    @Published var panels: [ViewerPanel] = [ViewerPanel()]
    /// 활성 패널 인덱스(트리에서 연 파일이 열리는 곳).
    @Published var activePanelIndex: Int = 0
    /// 각 패널의 폭 비율(가중치). panels와 길이 일치, 합으로 정규화해 사용.
    @Published var panelWeights: [CGFloat] = [1]

    /// 펼쳐진 폴더 URL 집합(트리 펼침 상태의 단일 출처).
    @Published var expandedURLs: Set<URL> = []
    /// 키보드 탐색 커서가 가리키는 노드 URL.
    @Published var cursorURL: URL?
    /// 다중 선택된 노드 URL 집합(Total Commander 스타일, Space/Insert로 토글).
    /// 커서(cursorURL)와는 독립적. 비어 있으면 단일 선택 모드(커서 항목만 대상).
    @Published var markedURLs: Set<URL> = []

    /// 키보드 포커스 영역: 트리 또는 특정 뷰어 패널.
    enum Focus: Equatable {
        case tree
        case panel(Int)
    }
    @Published var focus: Focus = .tree

    /// 현재 인라인 이름 편집 중인 노드 URL(없으면 nil).
    @Published var renamingURL: URL?
    /// 이름 변경 실패 시 사용자에게 보여줄 메시지(없으면 nil).
    @Published var renameError: String?
    /// 삭제 확인 대기 중인 노드 URL들(비어 있으면 대기 없음) — 확인 다이얼로그 표시용.
    /// 다중 선택 삭제를 지원하기 위해 배열로 관리한다.
    @Published var pendingDeleteURLs: [URL] = []

    static let maxPanels = 3

    /// 현재 선택(활성 패널에 열린) 파일 URL — 트리 강조용.
    var selectedURL: URL? { panels[safe: activePanelIndex]?.fileURL }

    /// 뷰어 본문 기준 폰트 크기(pt). 제목/코드 등은 이 값에 비례.
    @Published var viewerFontSize: CGFloat = WorkspaceStore.defaultFontSize {
        didSet { defaults.set(Double(viewerFontSize), forKey: Key.fontSize) }
    }

    static let defaultFontSize: CGFloat = 14
    static let minFontSize: CGFloat = 9
    static let maxFontSize: CGFloat = 28
    private static let fontStep: CGFloat = 1

    /// 트리 글자 크기(pt). 뷰어 본문과 따로 조절한다 — 트리는 훑는 목록이고
    /// 뷰어는 읽는 본문이라 편한 크기가 다르다.
    @Published var treeFontSize: CGFloat = Metrics.treeFontSize {
        didSet { defaults.set(Double(treeFontSize), forKey: Key.treeFontSize) }
    }

    /// 트리 행 높이. 글자가 커지면 행도 함께 커져야 글자가 잘리지 않는다.
    /// 기본값(12.5pt → 21pt)의 비율을 유지한다.
    var treeRowHeight: CGFloat {
        (treeFontSize * (Metrics.rowHeight / Metrics.treeFontSize)).rounded()
    }

    /// 트리 한 단계 들여쓰기 폭. 글자 크기에 비례해 계층이 계속 읽히게 한다.
    var treeIndentWidth: CGFloat {
        (treeFontSize * 1.12).rounded()
    }

    /// 내장 터미널 글자 크기(pt). 트리·뷰어와 별개로 기억한다.
    @Published var terminalFontSize: CGFloat = Metrics.terminalFontSize {
        didSet { defaults.set(Double(terminalFontSize), forKey: Key.terminalFontSize) }
    }

    /// 마우스가 지금 어느 영역 위에 있는지. ⌘+휠 확대 대상을 정하는 데 쓴다.
    ///
    /// 화면에 그리는 값이 아니라서 `@Published`로 두지 않는다 —
    /// 영역을 옮길 때마다 화면을 다시 그릴 이유가 없다.
    var hoverArea: HoverArea = .none

    enum HoverArea: Equatable {
        case none
        case tree
        case panel(Int)
        case terminal
    }

    /// 우측 터미널 패널 표시 여부(VSCode식 임베디드 터미널).
    @Published var showTerminal: Bool = false {
        didSet {
            guard oldValue != showTerminal else { return }
            defaults.set(showTerminal, forKey: Key.showTerminal)
        }
    }

    /// 터미널 패널이 붙는 자리.
    enum TerminalPosition: String {
        /// 뷰어 오른쪽(세로 패널).
        case right
        /// 뷰어 아래(가로 패널). 명령 출력이 넓게 펼쳐진다.
        case bottom
    }

    @Published var terminalPosition: TerminalPosition = .right {
        didSet {
            guard oldValue != terminalPosition else { return }
            defaults.set(terminalPosition.rawValue, forKey: Key.terminalPosition)
        }
    }

    // MARK: - 패널 크기
    //
    // 원래 이 값들은 @SceneStorage에 있었다. 그건 앱이 직접 저장하는 게 아니라 macOS의
    // 창 상태 복원에 얹혀 있어서, 강제 종료나 "종료 시 창 다시 열기"를 끈 환경에서는
    // 그대로 사라진다. 세션 복원은 이 앱의 핵심 가치라 직접 저장한다.

    /// 좌측 트리 폭.
    @Published var treeWidth: CGFloat = 280 {
        didSet { defaults.set(Double(treeWidth), forKey: Key.treeWidth) }
    }

    /// 오른쪽에 붙였을 때의 터미널 폭.
    @Published var terminalWidth: CGFloat = 420 {
        didSet { defaults.set(Double(terminalWidth), forKey: Key.terminalWidth) }
    }

    /// 아래쪽에 붙였을 때의 터미널 높이 — 폭과 따로 기억한다.
    @Published var terminalHeight: CGFloat = 260 {
        didSet { defaults.set(Double(terminalHeight), forKey: Key.terminalHeight) }
    }

    static let minTreeWidth: CGFloat = 180
    static let maxTreeWidth: CGFloat = 500
    static let minTerminalWidth: CGFloat = 260
    static let minTerminalHeight: CGFloat = 120

    func setTreeWidth(_ width: CGFloat) {
        treeWidth = min(max(width, Self.minTreeWidth), Self.maxTreeWidth)
    }

    func setTerminalWidth(_ width: CGFloat, limit: CGFloat) {
        terminalWidth = min(max(width, Self.minTerminalWidth), max(limit, Self.minTerminalWidth))
    }

    func setTerminalHeight(_ height: CGFloat, limit: CGFloat) {
        terminalHeight = min(max(height, Self.minTerminalHeight), max(limit, Self.minTerminalHeight))
    }

    /// 터미널을 오른쪽 ↔ 아래로 옮긴다.
    /// 실행 중인 셸은 그대로 유지된다(레이아웃만 바뀌고 뷰는 다시 만들지 않는다).
    func toggleTerminalPosition() {
        terminalPosition = terminalPosition == .right ? .bottom : .right
    }

    /// 터미널 패널 표시/숨김 토글(단축키·버튼용).
    func toggleTerminal() {
        showTerminal.toggle()
    }

    /// 터미널이 시작될 때 셸에 자동으로 입력할 명령(예: "claude").
    /// TerminalView가 셸 준비 후 이 값을 소비(주입 뒤 nil로 초기화)한다.
    /// 이미 실행 중인 셸에는 곧바로 주입하기 위해 클로저를 통해 전달한다.
    @Published var pendingTerminalCommand: String?

    /// 실행 중인 터미널 셸에 명령을 즉시 주입하는 콜백.
    /// TerminalView가 화면에 올라온 뒤 자신을 등록하고, 사라지면 nil로 지운다.
    var terminalCommandSink: ((String) -> Void)?

    /// Claude Code를 임베디드 터미널에서 실행한다.
    /// `--permission-mode auto`로 시작해 Shift+Tab 없이 처음부터 자동 수락 모드가 켜진다.
    /// 터미널이 이미 열려 있으면 실행 중인 셸에 바로 명령을 주입하고,
    /// 닫혀 있으면 터미널을 연 뒤 셸이 준비되면 주입되도록 예약한다.
    func launchClaudeCode() {
        let command = "claude --permission-mode auto"
        if showTerminal, let sink = terminalCommandSink {
            sink(command)
        } else {
            pendingTerminalCommand = command
            showTerminal = true
        }
    }

    /// 키보드 단축키 도움말 시트 표시 여부(Help 메뉴에서 연다).
    @Published var showShortcuts: Bool = false
    /// 지원 파일 형식 도움말 시트 표시 여부(Help ▸ 지원 파일 형식).
    @Published var showFileTypes: Bool = false
    /// 오픈소스 고지 시트 표시 여부(Help ▸ 오픈소스 라이선스).
    @Published var showAcknowledgements: Bool = false

    /// "폴더로 이동"(⌘⇧G) 시트 표시 여부.
    @Published var showGoToFolder: Bool = false

    /// 파일명으로 문서를 찾아 여는 창(⌘P) 표시 여부.
    @Published var showQuickOpen: Bool = false

    /// 폴더 전체 본문 검색 창(⇧⌘F) 표시 여부.
    @Published var showContentSearch: Bool = false

    /// 루트 하위 전체 파일 인덱스. 빠른 열기와 본문 검색이 함께 쓴다.
    let fileIndex = FileIndex()
    /// 본문 검색 상태(진행 중 결과를 담고 있다).
    let contentSearch = ContentSearch()

    /// 빠른 열기 창을 연다(⌘P). 루트가 없으면 열 것이 없다.
    func openQuickOpen() {
        guard root != nil else { return }
        showQuickOpen = true
    }

    /// 본문 검색 창을 연다(⇧⌘F).
    func openContentSearch() {
        guard root != nil else { return }
        showContentSearch = true
    }

    /// 본문 검색 결과에서 문서를 열고, 같은 검색어로 문서 내 찾기를 이어서 실행한다.
    /// 결과 줄로 곧장 뛰는 대신 이렇게 잇는 이유는 마크다운의 렌더 결과와 원문 줄 번호가
    /// 일대일로 맞지 않기 때문이다. 뷰어는 본문이 그려진 뒤에 검색을 수행한다.
    func openFromContentSearch(_ url: URL, query: String) {
        let index = activePanelIndex
        guard openMarkdown(at: url, inPanel: index) else { return }
        guard !query.isEmpty, panels[index].supportsFind else { return }
        panels[index].showFind = true
        setFindQuery(query, panel: index)
    }

    /// 전체 파일 표시 여부(false면 마크다운만). 변경 시 트리를 재스캔한다.
    @Published var showAllFiles: Bool = false {
        didSet {
            guard oldValue != showAllFiles else { return }
            FileNode.showAllFiles = showAllFiles
            defaults.set(showAllFiles, forKey: Key.showAllFiles)
            rescanAll()
            // 인덱스 범위(표시 필터)가 달라졌으니 검색도 다시 훑어야 한다.
            fileIndex.markStale()
        }
    }

    /// 트리 정렬 기준. 변경 시 트리를 재스캔한다(펼침 상태는 URL 기준이라 유지된다).
    @Published var sortOrder: SortOrder = SortOrder() {
        didSet {
            guard oldValue != sortOrder else { return }
            FileNode.sortOrder = sortOrder
            defaults.set(sortOrder.field.rawValue, forKey: Key.sortField)
            defaults.set(sortOrder.ascending, forKey: Key.sortAscending)
            rescanAll()
        }
    }

    /// 정렬 기준을 바꾼다. 같은 기준을 다시 고르면 방향을 뒤집는다(칼럼 헤더 관례).
    func setSortField(_ field: SortField) {
        if sortOrder.field == field {
            sortOrder.ascending.toggle()
        } else {
            sortOrder = SortOrder(field: field, ascending: field.defaultAscending)
        }
    }

    func toggleSortDirection() {
        sortOrder.ascending.toggle()
    }

    /// 지역화 문자열 헬퍼.
    private func L(_ key: L10n) -> String { LocalizationManager.shared.string(key) }

    private let defaults = UserDefaults.standard
    private enum Key {
        static let rootBookmark = "session.rootBookmark"
        static let openedFiles  = "session.openedFiles"   // 패널별 파일 경로 배열
        static let activePanel  = "session.activePanel"
        static let panelWeights = "session.panelWeights"
        static let fontSize     = "viewer.fontSize"
        static let treeFontSize = "tree.fontSize"
        static let terminalFontSize = "terminal.fontSize"
        static let terminalPosition = "ui.terminalPosition"
        static let treeWidth       = "ui.treeWidth"
        static let terminalWidth   = "ui.terminalWidthValue"
        static let terminalHeight  = "ui.terminalHeightValue"
        static let showAllFiles = "tree.showAllFiles"
        static let showTerminal = "ui.showTerminal"
        static let recentFolders = "session.recentFolders"
        static let sortField = "tree.sortField"
        static let sortAscending = "tree.sortAscending"
    }

    // MARK: - 최근 폴더 / 복원 실패

    /// 최근에 열었던 폴더. 환영 화면에서 한 번에 다시 열 수 있게 보관한다.
    @Published private(set) var recentFolders: [RecentFolder] = []

    static let maxRecentFolders = 8

    /// 지난 세션의 루트를 되살리지 못한 이유(없으면 nil).
    ///
    /// 폴더가 지워졌거나 옮겨졌거나 권한을 잃으면 복원이 실패한다. 예전에는 조용히
    /// 빈 화면으로 떨어져서, 사용자는 앱이 하던 일을 잊은 것처럼 느꼈다.
    @Published private(set) var restoreFailure: RestoreFailure?

    struct RestoreFailure: Equatable {
        /// 마지막으로 알던 경로(표시용). 북마크조차 못 풀면 nil.
        var path: String?
    }

    /// 환영 화면의 안내를 닫았는지(복원 실패 안내는 사용자가 치울 수 있어야 한다).
    func dismissRestoreFailure() { restoreFailure = nil }

    private func loadRecentFolders() {
        guard let data = defaults.data(forKey: Key.recentFolders),
              let saved = try? JSONDecoder().decode([RecentFolder].self, from: data)
        else { return }
        recentFolders = saved
    }

    /// 최근 목록 맨 앞에 올린다(중복은 위로 끌어올리고, 오래된 것은 잘라낸다).
    private func rememberRecentFolder(_ url: URL) {
        // 북마크를 같이 담아 둔다. 경로만으로는 보호된 위치(데스크톱·문서 등)를
        // 다시 열 때 권한이 없을 수 있다.
        let bookmark = try? url.bookmarkData(options: [.withSecurityScope],
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil)
        var list = recentFolders.filter { $0.path != url.path }
        list.insert(RecentFolder(path: url.path, bookmark: bookmark), at: 0)
        recentFolders = Array(list.prefix(Self.maxRecentFolders))
        if let encoded = try? JSONEncoder().encode(recentFolders) {
            defaults.set(encoded, forKey: Key.recentFolders)
        }
    }

    /// 최근 목록에서 폴더를 다시 연다. 북마크가 있으면 그걸로 권한을 되살린다.
    func openRecentFolder(_ recent: RecentFolder) {
        if let data = recent.bookmark {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: [.withSecurityScope],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale) {
                openFolder(url)
                return
            }
        }
        let url = URL(fileURLWithPath: recent.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // 사라진 폴더는 목록에서 지운다. 눌러도 아무 일 없는 항목을 남겨두지 않는다.
            removeRecentFolder(recent)
            restoreFailure = RestoreFailure(path: recent.path)
            return
        }
        openFolder(url)
    }

    func removeRecentFolder(_ recent: RecentFolder) {
        recentFolders.removeAll { $0.path == recent.path }
        if let encoded = try? JSONEncoder().encode(recentFolders) {
            defaults.set(encoded, forKey: Key.recentFolders)
        }
    }

    func clearRecentFolders() {
        recentFolders = []
        defaults.removeObject(forKey: Key.recentFolders)
    }

    /// 보안 스코프 접근을 유지 중인 루트 URL(stop을 위해 보관).
    private var accessedRootURL: URL?

    // MARK: - 폴더 열기

    /// NSOpenPanel로 폴더를 선택해 워크스페이스로 연다(메뉴 ⌘O·빈 화면 공용).
    func promptOpenFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L(.openPanelPrompt)
        panel.message = L(.openPanelMessage)
        if panel.runModal() == .OK, let url = panel.url {
            openFolder(url)
        }
    }

    /// "폴더로 이동"(⌘⇧G) 시트를 연다.
    func promptGoToFolder() {
        showGoToFolder = true
    }

    /// 입력한 경로를 정규화해 이동한다.
    /// - 폴더 경로면 그 폴더로 이동한다.
    /// - 파일 경로면 그 파일의 부모 폴더로 이동한 뒤 해당 파일을 커서로 선택한다.
    /// `~` 확장, 앞뒤 공백 제거를 처리한다. 이동에 성공하면 true.
    @discardableResult
    func goToPath(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        else { return false }

        if isDir.boolValue {
            openFolder(url)
            return true
        }

        // 파일: 부모 폴더로 이동한 뒤 그 파일을 트리에서 선택하고 뷰어에 연다.
        let parent = url.deletingLastPathComponent()
        openFolder(parent)
        // 사용자가 입력한 경로는 한글 자모 분리형(NFD)일 수 있는데, 파일시스템이
        // 스캔으로 돌려주는 URL은 완성형(NFC)이라 문자열 표현이 달라 == 비교가 어긋난다.
        // 부모 폴더의 실제 엔트리에서 같은 파일을 찾아 그 URL로 치환하면
        // 트리 노드와 정확히 일치해 선택 하이라이트가 제대로 표시된다.
        let fileURL = canonicalURL(for: url, in: parent) ?? url
        // 기본 표시 모드(showAllFiles=false)에서 대상 파일이 트리에 안 보이면
        // 전체 표시로 전환한다(전환 시 didSet이 rescanAll로 트리를 새로 만든다).
        // 반드시 재스캔 뒤에 파일을 열어야 새 root의 노드와 커서/펼침이 정합된다.
        let ext = fileURL.pathExtension.lowercased()
        if !FileNode.defaultVisibleExtensions.contains(ext) && !showAllFiles {
            showAllFiles = true
        }
        // 뷰어에 열면서 커서 선택·트리 펼침(revealInTree)까지 한번에 처리한다.
        openMarkdown(at: fileURL, inPanel: activePanelIndex)
        return true
    }

    /// 주어진 파일 URL과 동일 파일을 부모 폴더의 실제 스캔 결과에서 찾아
    /// 파일시스템이 돌려주는 정규화(NFC) URL을 반환한다. 못 찾으면 nil.
    /// 유니코드 정규화 차이로 == 비교가 어긋나는 것을 막기 위한 헬퍼.
    private func canonicalURL(for url: URL, in parent: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        // 경로 문자열을 NFC로 통일해 비교한다.
        let target = url.path.precomposedStringWithCanonicalMapping
        return entries.first { $0.path.precomposedStringWithCanonicalMapping == target }
    }

    /// 사용자가 고른 폴더를 루트로 설정하고 트리를 스캔한다.
    /// 보안 스코프 북마크를 저장해 다음 실행 때 권한을 복원한다.
    func openFolder(_ url: URL) {
        stopAccessingRoot()

        guard url.startAccessingSecurityScopedResource() else {
            // 직접 선택한 경우 보통 접근 가능하지만, 실패하면 왜 안 열렸는지 알려준다.
            restoreFailure = RestoreFailure(path: url.path)
            return
        }
        accessedRootURL = url
        restoreFailure = nil

        let node = FileNode(url: url, isDirectory: true)
        node.loadChildrenIfNeeded()
        root = node

        // 패널 초기화(1개, 빈 상태)
        panels = [ViewerPanel()]
        panelWeights = [1]
        activePanelIndex = 0
        expandedURLs = []
        cursorURL = node.children?.first?.url
        focus = .tree

        saveRootBookmark(url)
        rememberRecentFolder(url)
        persistOpenedFiles()
    }

    /// 트리의 하위 폴더로 진입(그 폴더를 새 루트로). 더블클릭/Enter용.
    /// 현재 루트의 하위라 보안 스코프 접근이 이미 유효하므로 루트만 교체한다.
    /// 열린 파일/패널은 유지한다.
    func enterFolder(_ node: FileNode) {
        guard node.isDirectory else { return }
        // 이미 접근 중인 루트의 하위인지 확인(권한 상속 범위).
        guard let root, node.url.path.hasPrefix(root.url.path) else { return }

        let newRoot = FileNode(url: node.url, isDirectory: true)
        newRoot.loadChildrenIfNeeded()
        self.root = newRoot

        // 진입한 폴더 기준으로 펼침/커서를 정리.
        expandedURLs = []
        cursorURL = newRoot.children?.first?.url
        markedURLs = []
        focus = .tree

        saveRootBookmark(node.url)
        persistOpenedFiles()
    }

    /// 현재 루트를 부모 폴더로 변경(상위로 이동). 열린 파일/패널은 유지한다.
    /// 부모에 접근할 수 없으면 false를 반환(아무 변화 없음).
    @discardableResult
    func goToParent() -> Bool {
        guard let current = root else { return false }
        let parentURL = current.url.deletingLastPathComponent()
        // 루트(/)에 도달했거나 동일하면 더 올라갈 수 없음.
        guard parentURL != current.url, parentURL.path != "/.." else { return false }

        // 부모 디렉터리를 나열할 수 있는지 확인(샌드박스 권한 체크).
        guard FileManager.default.isReadableFile(atPath: parentURL.path),
              (try? FileManager.default.contentsOfDirectory(atPath: parentURL.path)) != nil
        else { return false }

        // 보안 스코프 접근을 부모로 전환.
        stopAccessingRoot()
        if parentURL.startAccessingSecurityScopedResource() {
            accessedRootURL = parentURL
        }

        let previousRootURL = current.url
        let node = FileNode(url: parentURL, isDirectory: true)
        node.loadChildrenIfNeeded()
        root = node

        // 이전 루트 폴더를 펼친 상태로 두고 커서를 거기에 둔다.
        if let prev = node.children?.first(where: { $0.url == previousRootURL }) {
            if prev.isDirectory {
                prev.loadChildrenIfNeeded()
                expandedURLs.insert(prev.url)
            }
            cursorURL = prev.url
        } else {
            cursorURL = node.children?.first?.url
        }
        focus = .tree

        saveRootBookmark(parentURL)
        return true
    }

    /// 상위 이동(버튼/단축키용). 권한 문제로 직접 못 올라가면
    /// NSOpenPanel로 부모 폴더를 선택하게 유도한다(샌드박스 권한 획득).
    func goToParentOrPrompt() {
        if goToParent() { return }
        // 폴백: 부모 폴더를 사용자에게 직접 선택하게 해 접근 권한을 얻는다.
        guard let current = root else { return }
        let parentURL = current.url.deletingLastPathComponent()
        guard parentURL != current.url else { return }   // 이미 최상위

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = parentURL
        panel.message = L(.openPanelMessage)
        panel.prompt = L(.openPanelPrompt)
        if panel.runModal() == .OK, let chosen = panel.url {
            openFolder(chosen)
        }
    }

    /// 루트가 더 상위로 올라갈 수 있는지(버튼 활성화용).
    /// 파일시스템 최상위("/")가 아니면 항상 활성 — 권한이 없어도 버튼을 누르면
    /// NSOpenPanel 폴백으로 부모를 선택할 수 있게 한다(goToParentOrPrompt).
    var canGoToParent: Bool {
        guard let current = root else { return false }
        let parent = current.url.deletingLastPathComponent()
        return parent != current.url
    }

    // MARK: - 경로 복사 (VSCode 스타일)

    /// 항목의 전체(절대) 경로를 클립보드에 복사한다.
    func copyPath(_ url: URL) {
        writeToPasteboard(url.path)
    }

    /// 항목의 워크스페이스 루트 기준 상대 경로를 클립보드에 복사한다.
    /// 루트가 없거나 루트 밖이면 절대 경로로 대체한다.
    func copyRelativePath(_ url: URL) {
        writeToPasteboard(relativePath(of: url))
    }

    /// url을 현재 루트 기준 상대 경로 문자열로 변환. 루트 밖이면 절대 경로.
    private func relativePath(of url: URL) -> String {
        guard let root else { return url.path }
        let rootPath = root.url.path
        let target = url.path
        if target == rootPath { return root.url.lastPathComponent }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if target.hasPrefix(prefix) {
            return String(target.dropFirst(prefix.count))
        }
        return target
    }

    /// 문자열을 시스템 클립보드에 쓴다(기존 내용은 지운다).
    private func writeToPasteboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    // MARK: - 파일 선택 (활성 패널에 열기)

    func select(_ node: FileNode) {
        cursorURL = node.url
        guard !node.isDirectory else { return }
        // 마크다운은 렌더링, 그 외 파일은 평문으로 연다.
        openMarkdown(at: node.url, inPanel: activePanelIndex)
    }

    /// 지정한 패널에 파일을 연다(드래그앤드롭/직접 열기 공용).
    /// 마크다운이면 렌더링, 아니면 평문(isPlainText)으로 표시. 폴더는 무시.
    /// 성공하면 해당 패널을 활성으로 전환하고 트리도 동기화.
    @discardableResult
    func openMarkdown(at url: URL, inPanel index: Int) -> Bool {
        guard panels.indices.contains(index) else { return false }
        let ext = url.pathExtension.lowercased()
        // 디렉터리는 열지 않는다. 단 .pages·.rtfd처럼 패키지로 된 문서는
        // 디렉터리로 보이지만 뷰어가 파일 하나로 열어야 한다.
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue && !FileNode.richDocExtensions.contains(ext) { return false }
        let isMd = FileNode.markdownExtensions.contains(ext)
        let isPdf = FileNode.pdfExtensions.contains(ext)
        let isImg = FileNode.imageExtensions.contains(ext)
        let isHtml = FileNode.htmlExtensions.contains(ext)
        let isRich = FileNode.richDocExtensions.contains(ext)
        // 편집 중인 패널에 다른 파일을 열면 변경분을 먼저 저장하고 편집을 종료한다.
        if panels[index].isEditing {
            if panels[index].isDirty { _ = save(panel: index) }
            cancelEditing(panel: index)
        }
        // PDF·이미지·서식 문서는 바이너리라 텍스트로 읽지 않고 URL만 보관, 전용 뷰가 렌더링한다.
        let isBinary = isPdf || isImg || isRich
        let text = isBinary ? nil : ((try? String(contentsOf: url, encoding: .utf8)) ?? L(.cannotReadFile))
        panels[index].fileURL = url
        panels[index].content = text
        panels[index].isPDF = isPdf
        panels[index].isImage = isImg
        panels[index].isHTML = isHtml
        panels[index].isRichDoc = isRich
        // HTML은 WebView로 렌더링하므로 평문 취급에서 제외한다.
        panels[index].isPlainText = !isMd && !isBinary && !isHtml
        panels[index].pdfZoom = 0   // 새 파일은 폭 맞춤으로 시작
        // 쪽 표시는 새 문서를 뷰가 읽고 나서 다시 채운다.
        panels[index].pdfPage = 0
        panels[index].pdfPageCount = 0
        // 이전 문서에서 찾던 결과는 무효다. 바는 열어둔 채 검색 상태만 비운다.
        panels[index].findRequest = nil
        panels[index].findMissed = false
        // 이미 변환해 둔 PDF가 있으면 곧바로 그걸로 시작한다(두 번째부터는 대기 없음).
        panels[index].richDocPDF = isRich ? DocumentConverter.cachedPDF(for: url) : nil
        panels[index].isConverting = false
        // 이 문서를 전에 QuickLook으로 보기로 골랐다면 그대로 이어 간다.
        panels[index].prefersQuickLook = isRich && quickLookPreferred.contains(url)
        activePanelIndex = index
        cursorURL = url
        revealInTree(url)
        persistOpenedFiles()
        // 캐시가 없으면 QuickLook을 먼저 보여주면서 뒤에서 변환한다.
        startConversionIfNeeded(panel: index)
        return true
    }

    // MARK: - 서식 문서 → PDF 변환

    /// 패널별 변환 작업. 다른 파일로 옮겨 가면 이전 작업은 취소한다.
    private var conversionTasks: [Int: Task<Void, Never>] = [:]

    /// 서식 문서를 연 패널에서 PDF 변환을 시작한다.
    /// QuickLook 표시는 그대로 두고, 변환이 끝나면 더 정확한 PDF로 갈아 끼운다.
    private func startConversionIfNeeded(panel index: Int) {
        conversionTasks[index]?.cancel()
        conversionTasks[index] = nil

        guard let panel = panels[safe: index], let url = panel.fileURL,
              panel.isRichDoc, panel.richDocPDF == nil, !panel.prefersQuickLook,
              DocumentConverter.canConvert(url) else { return }

        panels[index].isConverting = true
        conversionTasks[index] = Task { [weak self] in
            let pdf = await DocumentConverter.shared.pdf(for: url)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                // 변환하는 동안 사용자가 다른 파일로 옮겨 갔으면 반영하지 않는다.
                guard let current = self.panels[safe: index], current.fileURL == url else { return }
                self.panels[index].richDocPDF = pdf
                self.panels[index].isConverting = false
            }
        }
    }

    // MARK: - 편집 / 저장

    /// 지정 패널의 편집 모드를 켠다. 현재 본문을 편집 초안으로 복사한다.
    /// 서식 문서(Word·RTF)는 텍스트 본문이 없어 편집하면 빈 파일로 덮어쓰게 되므로 막는다.
    func beginEditing(panel index: Int) {
        guard panels.indices.contains(index), panels[index].fileURL != nil,
              !panels[index].isRichDoc else { return }
        panels[index].draft = panels[index].content ?? ""
        panels[index].isEditing = true
        // 편집 모드에는 아직 검색 수단이 없다. 열려 있던 찾기 바를 접는다.
        closeFind(panel: index)
        activePanelIndex = index
        focus = .panel(index)
    }

    /// 편집 모드를 끈다. 저장하지 않은 변경은 버린다(호출 측에서 확인 책임).
    func cancelEditing(panel index: Int) {
        guard panels.indices.contains(index) else { return }
        panels[index].isEditing = false
        panels[index].draft = ""
    }

    /// 보기/편집 토글. 편집→보기 전환 시 변경분이 있으면 먼저 저장한다.
    func toggleEditing(panel index: Int) {
        guard panels.indices.contains(index), panels[index].fileURL != nil else { return }
        if panels[index].isEditing {
            if panels[index].isDirty { _ = save(panel: index) }
            cancelEditing(panel: index)
        } else {
            beginEditing(panel: index)
        }
    }

    /// 활성 패널 편집 토글(단축키용).
    func toggleEditingActivePanel() { toggleEditing(panel: activePanelIndex) }

    /// 지정 패널의 초안을 디스크에 쓰고 content에 반영한다. 성공 시 true.
    @discardableResult
    func save(panel index: Int) -> Bool {
        guard panels.indices.contains(index),
              let url = panels[index].fileURL,
              panels[index].isEditing else { return false }

        let text = panels[index].draft
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            renameError = L(.saveFailed(error.localizedDescription))
            return false
        }
        panels[index].content = text

        // 같은 파일을 연 다른 패널들의 본문도 동기화한다.
        for i in panels.indices where i != index && panels[i].fileURL == url {
            panels[i].content = text
            if panels[i].isEditing { panels[i].draft = text }
        }
        return true
    }

    /// 활성 패널 저장(단축키용). 편집 중이 아니면 무시.
    @discardableResult
    func saveActivePanel() -> Bool { save(panel: activePanelIndex) }

    /// 어느 패널이든 저장하지 않은 변경이 있는지(창 닫기 경고 등에 활용 가능).
    var hasUnsavedChanges: Bool { panels.contains { $0.isDirty } }

    // MARK: - 문서 내 찾기

    /// 검색 요청 일련번호. 같은 문자열로 "다음"을 눌러도 새 요청으로 보이게 하는 용도.
    private var findSequence: Int = 0

    /// ⌘F를 다시 눌렀을 때 이미 열려 있는 찾기 바의 입력으로 포커스를 되돌리기 위한 신호.
    @Published private(set) var findFocusToken: Int = 0

    /// 활성 패널이 문서 내 찾기를 쓸 수 있는 상태인지(메뉴 활성화 판단).
    var canFindInActivePanel: Bool {
        panels[safe: activePanelIndex]?.supportsFind ?? false
    }

    /// 활성 패널에 찾기 바를 연다(⌘F). 이미 열려 있으면 입력을 다시 고르게 둔다.
    func openFind() {
        let index = activePanelIndex
        guard panels.indices.contains(index), panels[index].supportsFind else { return }
        panels[index].showFind = true
        focus = .panel(index)
        findFocusToken += 1
    }

    func closeFind(panel index: Int) {
        guard panels.indices.contains(index) else { return }
        panels[index].showFind = false
        panels[index].findRequest = nil
        panels[index].findMissed = false
    }

    /// 입력이 바뀔 때마다 첫 결과로 이동한다(증분 검색).
    func setFindQuery(_ query: String, panel index: Int) {
        guard panels.indices.contains(index) else { return }
        panels[index].findQuery = query
        guard !query.isEmpty else {
            panels[index].findRequest = nil
            panels[index].findMissed = false
            return
        }
        requestFind(panel: index, forward: true, isNewSearch: true)
    }

    /// 다음/이전 결과로 이동. 입력이 비어 있으면 아무것도 하지 않는다.
    func findAgain(panel index: Int, forward: Bool) {
        guard panels.indices.contains(index),
              !panels[index].findQuery.isEmpty else { return }
        requestFind(panel: index, forward: forward, isNewSearch: false)
    }

    /// 활성 패널에서 다음 결과로(⌘G). 찾기 바가 닫혀 있으면 먼저 연다.
    func findNextInActivePanel() {
        let index = activePanelIndex
        guard panels.indices.contains(index), panels[index].supportsFind else { return }
        if !panels[index].showFind { panels[index].showFind = true }
        findAgain(panel: index, forward: true)
    }

    private func requestFind(panel index: Int, forward: Bool, isNewSearch: Bool) {
        findSequence += 1
        panels[index].findRequest = FindRequest(
            query: panels[index].findQuery, forward: forward,
            isNewSearch: isNewSearch, sequence: findSequence)
    }

    /// 뷰어가 검색 결과를 알려준다(결과 없으면 입력 필드를 강조).
    func reportFindResult(found: Bool, panel index: Int) {
        guard panels.indices.contains(index) else { return }
        panels[index].findMissed = !found
    }

    // MARK: - 읽던 위치 기억

    /// 문서별 마지막 스크롤 위치(0~1).
    ///
    /// 뷰어는 폰트·테마가 바뀌거나 편집을 오갈 때 문서를 통째로 다시 그린다. 그때마다
    /// 처음으로 튀지 않도록 위치를 기억해 이어 붙인다. 다른 파일을 보고 돌아왔을 때도
    /// 같은 위치에서 이어 읽는다.
    ///
    /// 스크롤 중 계속 갱신되는 값이라 `@Published`로 두지 않는다(매번 뷰를 다시 그릴 이유가 없다).
    private var viewerScrollRatios: [URL: Double] = [:]

    func viewerScrollRatio(for url: URL?) -> Double {
        guard let url else { return 0 }
        return viewerScrollRatios[url] ?? 0
    }

    func setViewerScrollRatio(_ ratio: Double, for url: URL?) {
        guard let url, ratio.isFinite else { return }
        viewerScrollRatios[url] = min(max(ratio, 0), 1)
    }

    /// 서식 문서를 QuickLook으로 보겠다고 사용자가 고른 문서들.
    ///
    /// 두 렌더러가 서로 다른 방식으로 어긋난다. 변환 PDF는 표 폭·글꼴이 정확한 대신
    /// 사진이 많은 표에서 페이지 경계에 걸린 행이 갈라지고, QuickLook은 그 문제가 없는
    /// 대신 표 폭이 뭉친다. 어느 쪽이 나은지는 문서마다 달라 사용자가 고르게 하고,
    /// 그 선택을 문서별로 기억한다.
    private var quickLookPreferred: Set<URL> = []

    /// 현재 패널의 서식 문서 렌더러를 QuickLook ↔ 변환 PDF로 전환한다.
    func toggleRichDocRenderer(panel index: Int) {
        guard let panel = panels[safe: index], let url = panel.fileURL, panel.isRichDoc else { return }
        let toQuickLook = !panel.prefersQuickLook
        panels[index].prefersQuickLook = toQuickLook
        if toQuickLook {
            quickLookPreferred.insert(url)
        } else {
            quickLookPreferred.remove(url)
            // PDF로 되돌아가는데 아직 변환본이 없으면(캐시 삭제 등) 다시 변환한다.
            startConversionIfNeeded(panel: index)
        }
        // 렌더러가 바뀌면 쪽 표시·배율은 의미가 달라진다. 초기화한다.
        panels[index].pdfPage = 0
        panels[index].pdfPageCount = 0
        panels[index].pdfZoom = 0
    }

    // MARK: - 터미널에서 열기

    /// 임베디드 터미널이 시작할 폴더. 트리 커서 기준(폴더면 자신, 파일이면 부모),
    /// 커서가 없으면 루트. 루트도 없으면 홈 디렉터리.
    var terminalStartDirectory: URL {
        targetDirectory(for: node(for: cursorURL))
    }

    /// 주어진 노드 위치를 시스템 터미널에서 연다(폴더면 자신, 파일이면 부모).
    /// nil이면 현재 루트. 샌드박스에서도 NSWorkspace로 Terminal.app에 폴더를 넘긴다.
    func openInTerminal(near node: FileNode?) {
        let dir = targetDirectory(for: node)
        openTerminal(at: dir)
    }

    /// 커서 위치 기준으로 터미널 열기(메뉴/단축키용). 루트가 없으면 무시.
    func openInTerminalAtCursor() {
        guard root != nil else { return }
        openInTerminal(near: node(for: cursorURL))
    }

    /// 지정한 폴더 URL을 Terminal.app으로 연다.
    /// Terminal.app 경로는 OS 버전에 따라 다를 수 있어 후보를 순회한다.
    private func openTerminal(at dir: URL) {
        let ws = NSWorkspace.shared
        let candidates = [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/Utilities/Terminal.app",
        ].map { URL(fileURLWithPath: $0) }

        let terminal = candidates.first { FileManager.default.fileExists(atPath: $0.path) }
            ?? ws.urlForApplication(withBundleIdentifier: "com.apple.Terminal")

        let config = NSWorkspace.OpenConfiguration()
        if let terminal {
            ws.open([dir], withApplicationAt: terminal, configuration: config) { _, error in
                // 권한 등으로 실패하면 폴더를 기본 방식으로 열어 최소한의 동작을 보장.
                if error != nil { ws.open(dir) }
            }
        } else {
            ws.open(dir)
        }
    }

    // MARK: - 다중 선택 (Total Commander 스타일)

    /// 노드가 다중 선택(mark)되어 있는지.
    func isMarked(_ url: URL) -> Bool { markedURLs.contains(url) }

    /// 커서 항목의 선택을 토글(Space). 커서는 그대로 둔다.
    func toggleMarkAtCursor() {
        guard renamingURL == nil, let url = cursorURL else { return }
        if markedURLs.contains(url) { markedURLs.remove(url) } else { markedURLs.insert(url) }
    }

    /// 커서 항목을 토글하고 커서를 한 칸 아래로(Insert). TC의 빠른 다중 선택.
    func toggleMarkAndAdvance() {
        guard renamingURL == nil, let url = cursorURL else { return }
        if markedURLs.contains(url) { markedURLs.remove(url) } else { markedURLs.insert(url) }
        moveCursorOnly(by: 1)
    }

    /// 모든 선택 해제.
    func clearMarks() {
        if !markedURLs.isEmpty { markedURLs = [] }
    }

    /// 현재 커서(anchor)부터 target까지 보이는 범위를 선택(Shift+클릭).
    /// anchor가 없으면 target만 선택. 커서는 target으로 이동한다.
    func markRange(to target: URL) {
        guard renamingURL == nil else { return }
        let nodes = visibleNodes
        guard let endIdx = nodes.firstIndex(where: { $0.url == target }) else { return }
        let anchor = cursorURL ?? target
        let startIdx = nodes.firstIndex(where: { $0.url == anchor }) ?? endIdx
        let lo = min(startIdx, endIdx)
        let hi = max(startIdx, endIdx)
        for i in lo...hi { markedURLs.insert(nodes[i].url) }
        cursorURL = target
    }

    /// 단일 토글(Cmd+클릭): 해당 항목만 선택 토글, 커서 이동.
    func toggleMark(_ url: URL) {
        guard renamingURL == nil else { return }
        if markedURLs.contains(url) { markedURLs.remove(url) } else { markedURLs.insert(url) }
        cursorURL = url
    }

    /// 현재 작업(복사/삭제 등) 대상 URL 목록.
    /// 선택된 항목이 있으면 그 전체, 없으면 커서 항목 1개.
    /// 트리 표시 순서(visibleNodes)를 따라 안정적으로 정렬해 반환한다.
    var actionTargetURLs: [URL] {
        if !markedURLs.isEmpty {
            return visibleNodes.map { $0.url }.filter { markedURLs.contains($0) }
        }
        if let c = cursorURL { return [c] }
        return []
    }

    /// 선택 개수(상태 표시용). 선택이 없으면 0.
    var markedCount: Int { markedURLs.count }

    // MARK: - 상태바 정보

    /// 현재 커서가 가리키는 노드(상태바 표시용).
    var cursorNode: FileNode? { node(for: cursorURL) }

    /// 루트 바로 아래(현재 폴더)의 항목 수.
    var currentFolderItemCount: Int { root?.children?.count ?? 0 }

    /// 마크된 항목들의 총 바이트 크기(폴더는 0으로 계산 — 재귀 비용 회피).
    var markedTotalSize: Int64 {
        markedURLs.reduce(0) { $0 + Self.fileSize(of: $1) }
    }

    /// 주어진 URL의 파일 크기(바이트). 폴더/실패 시 0.
    static func fileSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values?.isDirectory == true { return 0 }
        return Int64(values?.fileSize ?? 0)
    }

    // MARK: - 멀티 리네임 (Total Commander Multi-Rename Tool)

    /// 멀티 리네임 시트 표시 여부.
    @Published var showMultiRename: Bool = false
    /// 멀티 리네임 대상 URL들(시트가 열릴 때 고정 캡처). 표시 순서대로.
    @Published var renameTargets: [URL] = []

    /// 멀티 리네임 시트를 연다. 대상: 마크된 항목 전체(없으면 커서 1개).
    func openMultiRename() {
        guard renamingURL == nil else { return }
        let targets = actionTargetURLs
        guard !targets.isEmpty else { return }
        renameTargets = targets
        showMultiRename = true
    }

    /// 미리보기 항목들을 실제 디스크에 적용한다. 충돌/무변경 항목은 건너뛴다.
    /// 두 단계(임시 이름 → 최종 이름)로 처리해 대상 간 이름 교환/연쇄 충돌을 피한다.
    /// 성공 시 트리/상태를 갱신하고 시트를 닫는다.
    func applyMultiRename(_ items: [RenamePreviewItem]) {
        let valid = items.filter { $0.changed && $0.issue == nil }
        guard !valid.isEmpty else { showMultiRename = false; return }

        let fm = FileManager.default
        var renamed: [(from: URL, to: URL)] = []

        // 1단계: 모든 대상을 고유 임시 이름으로 옮긴다(상호 충돌 회피).
        var temps: [(temp: URL, final: URL, original: URL)] = []
        for it in valid {
            let dir = it.url.deletingLastPathComponent()
            let finalURL = dir.appendingPathComponent(it.newName)
            let tempURL = dir.appendingPathComponent(".mrt-\(UUID().uuidString)-\(it.newName)")
            do {
                try fm.moveItem(at: it.url, to: tempURL)
                temps.append((tempURL, finalURL, it.url))
            } catch {
                renameError = L(.renameFailed(error.localizedDescription))
            }
        }
        // 2단계: 임시 → 최종.
        for t in temps {
            do {
                try fm.moveItem(at: t.temp, to: t.final)
                renamed.append((t.original, t.final))
            } catch {
                // 실패 시 원래 이름으로 되돌리려 시도.
                try? fm.moveItem(at: t.temp, to: t.original)
                renameError = L(.renameFailed(error.localizedDescription))
            }
        }

        // 영향받은 폴더 재스캔 + 열린 패널/펼침/커서 경로 이전.
        let dirs = Set(renamed.map { $0.from.deletingLastPathComponent() })
        for dir in dirs { rescanDirectory(dir) }
        for r in renamed { migratePaths(from: r.from, to: r.to) }

        objectWillChange.send()
        clearMarks()
        persistOpenedFiles()
        showMultiRename = false
    }

    // MARK: - Function Key 동작 (Total Commander 스타일)
    //
    // F-key는 메뉴 커맨드(.keyboardShortcut)로 등록되어 포커스 위치와 무관하게
    // 항상 동작한다. 인라인 이름 편집 중에는 TextField 입력을 방해하지 않도록
    // 모든 F-key를 무시한다.

    /// F3 보기: 커서가 마크다운 파일이면 활성 패널에 열고, 편집 중이면 미리보기로 전환.
    func fkeyView() {
        guard renamingURL == nil else { return }
        if let node = node(for: cursorURL), node.isViewable {
            select(node)
        }
        if panels[safe: activePanelIndex]?.isEditing == true {
            toggleEditing(panel: activePanelIndex)   // 편집→보기(필요 시 저장)
        }
    }

    /// F4 편집: 커서가 마크다운 파일이면 활성 패널에 연 뒤 편집 모드로.
    func fkeyEdit() {
        guard renamingURL == nil else { return }
        if let node = node(for: cursorURL), node.isMarkdown,
           panels[safe: activePanelIndex]?.fileURL != node.url {
            select(node)
        }
        if panels[safe: activePanelIndex]?.fileURL != nil,
           panels[safe: activePanelIndex]?.isEditing == false {
            beginEditing(panel: activePanelIndex)
        }
    }

    /// F5 복사: 작업 대상(선택 전체 또는 커서 1개)을 각자 같은 폴더에 "사본"으로 복제.
    func fkeyCopyAtCursor() {
        guard renamingURL == nil else { return }
        let targets = actionTargetURLs
        guard !targets.isEmpty else { return }
        for url in targets {
            _ = dropItem(url, into: url.deletingLastPathComponent(), copy: true)
        }
        clearMarks()
    }

    /// F6 이름변경: 커서 항목 인라인 이름 편집 시작.
    func fkeyRenameAtCursor() {
        guard renamingURL == nil, let node = node(for: cursorURL) else { return }
        beginRename(node)
    }

    // MARK: - 트리 펼침

    func isExpanded(_ node: FileNode) -> Bool { expandedURLs.contains(node.url) }

    func toggleExpand(_ node: FileNode) {
        guard node.isDirectory else { return }
        if expandedURLs.contains(node.url) {
            expandedURLs.remove(node.url)
        } else {
            node.loadChildrenIfNeeded()
            expandedURLs.insert(node.url)
        }
    }

    func expand(_ node: FileNode) {
        guard node.isDirectory, !expandedURLs.contains(node.url) else { return }
        node.loadChildrenIfNeeded()
        expandedURLs.insert(node.url)
    }

    func collapse(_ node: FileNode) {
        expandedURLs.remove(node.url)
    }

    // MARK: - 펼쳐진 항목의 평면 목록 (키보드 탐색용)

    /// 현재 펼침 상태 기준으로 화면에 보이는 노드들을 위→아래 순서로 평탄화.
    var visibleNodes: [FileNode] {
        guard let root else { return [] }
        var result: [FileNode] = []
        func walk(_ nodes: [FileNode]) {
            for node in nodes {
                result.append(node)
                if node.isDirectory, expandedURLs.contains(node.url),
                   let children = node.children {
                    walk(children)
                }
            }
        }
        walk(root.children ?? [])
        return result
    }

    private func node(for url: URL?) -> FileNode? {
        guard let url, let root else { return nil }
        return root.findNode(url: url)
    }

    // MARK: - 키보드 탐색 (트리)

    /// 커서를 위/아래로 이동. 파일이면 즉시 활성 패널에 열어 미리보기.
    func moveCursor(by delta: Int) {
        let nodes = visibleNodes
        guard !nodes.isEmpty else { return }
        let currentIndex = nodes.firstIndex { $0.url == cursorURL } ?? -1
        let next = min(max(currentIndex + delta, 0), nodes.count - 1)
        let node = nodes[next]
        cursorURL = node.url
        if node.isViewable { select(node) }   // 이동=미리보기(마크다운·PDF)
    }

    /// 커서만 위/아래로 이동(미리보기·선택 변경 없음). Insert 다중 선택용.
    func moveCursorOnly(by delta: Int) {
        let nodes = visibleNodes
        guard !nodes.isEmpty else { return }
        let currentIndex = nodes.firstIndex { $0.url == cursorURL } ?? -1
        let next = min(max(currentIndex + delta, 0), nodes.count - 1)
        cursorURL = nodes[next].url
    }

    /// → : 폴더면 펼치기(이미 펼쳐졌으면 첫 자식으로). 파일이면 무시.
    func expandOrEnter() {
        guard let node = node(for: cursorURL) else { return }
        if node.isDirectory {
            if expandedURLs.contains(node.url) {
                if let first = node.children?.first { cursorURL = first.url }
            } else {
                expand(node)
            }
        }
    }

    /// ← : 펼친 폴더면 접기. 아니면 부모로 이동.
    func collapseOrParent() {
        guard let node = node(for: cursorURL) else { return }
        if node.isDirectory, expandedURLs.contains(node.url) {
            collapse(node)
        } else if let parent = parentNode(of: node) {
            cursorURL = parent.url
        }
    }

    /// Enter : 파일이면 활성 패널에 열기, 폴더면 펼침 토글.
    func activateCursor() {
        guard let node = node(for: cursorURL) else { return }
        if node.isDirectory {
            toggleExpand(node)
        } else {
            select(node)
        }
    }

    /// 루트 children 중 cursor 노드의 부모를 찾는다.
    private func parentNode(of target: FileNode) -> FileNode? {
        guard let root else { return nil }
        let parentURL = target.url.deletingLastPathComponent()
        if parentURL == root.url { return nil }   // 루트 직계면 부모 없음
        return root.findNode(url: parentURL)
    }

    // MARK: - 포커스 / Tab 순환

    /// Tab: 트리 → 패널0 → 패널1 → … → 트리 순으로 포커스 이동.
    func focusNext() {
        switch focus {
        case .tree:
            focus = .panel(0)
            activePanelIndex = 0
        case .panel(let i):
            if i + 1 < panels.count {
                focus = .panel(i + 1)
                activePanelIndex = i + 1
            } else {
                focus = .tree
            }
        }
    }

    /// Shift+Tab: 역방향.
    func focusPrevious() {
        switch focus {
        case .tree:
            let last = panels.count - 1
            focus = .panel(last)
            activePanelIndex = last
        case .panel(let i):
            if i - 1 >= 0 {
                focus = .panel(i - 1)
                activePanelIndex = i - 1
            } else {
                focus = .tree
            }
        }
    }

    /// 패널을 활성으로 전환(포커스도 함께 이동). 트리를 그 패널 파일로 동기화.
    func activatePanel(_ index: Int) {
        guard panels.indices.contains(index) else { return }
        activePanelIndex = index
        focus = .panel(index)
        if let url = panels[index].fileURL {
            revealInTree(url)
        }
    }

    /// 트리에서 주어진 파일 위치를 드러낸다: 경로상의 폴더를 펼치고 커서를 그 파일로.
    func revealInTree(_ url: URL) {
        guard let root else { return }
        guard url.path.hasPrefix(root.url.path) else { return }
        expandPath(to: url, from: root)
        cursorURL = url
    }

    // MARK: - 새 파일 / 폴더 생성

    /// 기준 노드(폴더면 자신, 파일이면 부모)를 대상 폴더로 새 항목을 만든다.
    /// nil이면 루트에 생성. 생성 후 인라인 이름 편집 모드로 진입한다.
    func createMarkdownFile(near node: FileNode?) {
        createItem(near: node, baseName: L(.newDocumentName), ext: "md", isDirectory: false)
    }

    func createFolder(near node: FileNode?) {
        createItem(near: node, baseName: L(.newFolder), ext: nil, isDirectory: true)
    }

    /// 메뉴/단축키용: 현재 커서 위치를 기준으로 생성.
    func createMarkdownFileAtCursor() {
        guard renamingURL == nil else { return }
        createMarkdownFile(near: node(for: cursorURL))
    }
    func createFolderAtCursor() {
        guard renamingURL == nil else { return }
        createFolder(near: node(for: cursorURL))
    }

    private func createItem(near node: FileNode?, baseName: String, ext: String?, isDirectory: Bool) {
        renameError = nil
        let dirURL = targetDirectory(for: node)
        let fm = FileManager.default

        // 중복되지 않는 이름 생성.
        let url = uniqueChildURL(in: dirURL, baseName: baseName, ext: ext)

        do {
            if isDirectory {
                try fm.createDirectory(at: url, withIntermediateDirectories: false)
            } else {
                try "".write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            renameError = L(.createFailed(error.localizedDescription))
            return
        }

        // 대상 폴더를 펼치고 재스캔.
        if let dir = (dirURL == root?.url ? root : root?.findNode(url: dirURL)) {
            dir.children = FileNode.scan(directory: dirURL)
        }
        expandedURLs.insert(dirURL)
        objectWillChange.send()

        // 새 항목으로 커서 이동 + 인라인 편집 시작.
        cursorURL = url
        renamingURL = url
    }

    /// 기준 노드로부터 새 항목을 만들 폴더 URL을 정한다.
    private func targetDirectory(for node: FileNode?) -> URL {
        guard let node else { return root?.url ?? URL(fileURLWithPath: NSHomeDirectory()) }
        return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
    }

    /// dir 안에서 중복되지 않는 "baseName", "baseName 2" … URL을 찾는다.
    private func uniqueChildURL(in dir: URL, baseName: String, ext: String?) -> URL {
        let fm = FileManager.default
        var n = 1
        while true {
            let stem = n == 1 ? baseName : "\(baseName) \(n)"
            let name = (ext == nil || ext!.isEmpty) ? stem : "\(stem).\(ext!)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    // MARK: - 삭제 (휴지통으로 이동)

    /// 삭제 확인 다이얼로그 띄우기(단일).
    func requestDelete(_ node: FileNode) {
        pendingDeleteURLs = [node.url]
    }

    /// 삭제 요청(단축키/F8용): 선택 항목이 있으면 전체, 없으면 커서 1개.
    func requestDeleteAtCursor() {
        guard renamingURL == nil else { return }
        let targets = actionTargetURLs
        guard !targets.isEmpty else { return }
        pendingDeleteURLs = targets
    }

    /// 확인 후 실제 삭제: 대기 중인 모든 항목을 휴지통으로 이동하고 트리/상태를 갱신.
    func confirmDelete() {
        let urls = pendingDeleteURLs
        defer { pendingDeleteURLs = []; clearMarks() }
        guard !urls.isEmpty else { return }

        var deleted: [URL] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                deleted.append(url)
            } catch {
                // 일부 실패해도 나머지는 계속 진행. 마지막 오류를 표시.
                renameError = L(.deleteFailed(error.localizedDescription))
            }
        }
        guard !deleted.isEmpty else { return }

        // 영향받은 부모 폴더들을 재스캔(중복 제거).
        let parents = Set(deleted.map { $0.deletingLastPathComponent() })
        for dir in parents { rescanDirectory(dir) }

        // 관련 상태 정리: 펼침/커서/열린 패널에서 삭제된 경로(및 하위) 제거.
        func affected(_ u: URL) -> Bool {
            deleted.contains { u == $0 || u.path.hasPrefix($0.path + "/") }
        }
        expandedURLs = expandedURLs.filter { !affected($0) }
        if let c = cursorURL, affected(c) { cursorURL = nil }
        for i in panels.indices {
            if let f = panels[i].fileURL, affected(f) {
                panels[i].fileURL = nil
                panels[i].content = nil
                panels[i].isEditing = false
                panels[i].draft = ""
            }
        }
        objectWillChange.send()
        persistOpenedFiles()
    }

    func cancelDelete() { pendingDeleteURLs = [] }

    /// 삭제 확인 다이얼로그에 표시할 이름(단일이면 파일명, 다중이면 "N개 항목").
    var pendingDeleteName: String {
        if pendingDeleteURLs.count == 1 {
            return pendingDeleteURLs[0].lastPathComponent
        }
        return ""   // 다중일 때는 confirmDeleteMulti 메시지를 사용
    }

    /// 삭제 대기 항목 개수.
    var pendingDeleteCount: Int { pendingDeleteURLs.count }

    // MARK: - 이름 변경

    /// 인라인 편집 시작.
    func beginRename(_ node: FileNode) {
        renameError = nil
        renamingURL = node.url
    }

    func cancelRename() {
        renamingURL = nil
    }

    /// 노드의 이름을 newName으로 변경. 성공하면 부모를 재스캔해 트리를 갱신한다.
    func commitRename(_ node: FileNode, to newName: String) {
        defer { renamingURL = nil }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        // 변화 없음 / 빈 이름 / 경로 구분자 포함은 무시.
        guard !trimmed.isEmpty, trimmed != node.name else { return }
        guard !trimmed.contains("/"), !trimmed.contains(":") else {
            renameError = L(.invalidNameChars)
            return
        }

        let destination = node.url.deletingLastPathComponent().appendingPathComponent(trimmed)

        // 이미 존재하는 이름이면 거부.
        if FileManager.default.fileExists(atPath: destination.path) {
            renameError = L(.alreadyExists(trimmed))
            return
        }

        do {
            try FileManager.default.moveItem(at: node.url, to: destination)
        } catch {
            renameError = L(.renameFailed(error.localizedDescription))
            return
        }

        // 부모 폴더를 재스캔해 새 URL의 노드로 교체.
        let wasExpanded = expandedURLs.contains(node.url)
        let wasCursor = cursorURL == node.url
        rescanParent(of: node)

        // 펼침/커서/열린 패널의 URL을 새 경로로 이전.
        if wasExpanded {
            expandedURLs.remove(node.url)
            expandedURLs.insert(destination)
        }
        if wasCursor { cursorURL = destination }
        for i in panels.indices where panels[i].fileURL == node.url {
            panels[i].fileURL = destination
        }
        persistOpenedFiles()
    }

    /// 주어진 노드의 부모 폴더 children을 다시 스캔한다(루트 직계면 루트 재스캔).
    private func rescanParent(of node: FileNode) {
        rescanDirectory(node.url.deletingLastPathComponent())
    }

    /// 루트와 현재 로드된 모든 폴더를 재스캔한다(필터 변경 등 전역 갱신용).
    ///
    /// scan()이 만드는 새 자식 노드는 children == nil(미로드)이므로, 재귀 시
    /// "원래 로드돼 있었는지"를 부모에서 판단해 넘긴다. 그래야 펼쳐져 있던
    /// 하위 폴더가 재스캔 뒤에도 children을 다시 채워 펼침 상태를 유지한다.
    private func rescanAll() {
        guard let root else { return }
        // node의 children이 이미 로드돼 있었을 때만 재스캔한다.
        // 재스캔으로 교체된 새 자식들은, 펼쳐져 있던(expandedURLs) 것만 다시 로드해
        // 하위로 재귀한다.
        func walk(_ node: FileNode, wasLoaded: Bool) {
            guard node.isDirectory, wasLoaded else { return }
            node.children = FileNode.scan(directory: node.url)
            for child in node.children ?? [] {
                // 새 자식은 항상 미로드 상태이므로, 펼쳐져 있던 폴더만 이어서 로드한다.
                walk(child, wasLoaded: expandedURLs.contains(child.url))
            }
        }
        walk(root, wasLoaded: root.children != nil)
        // 더 이상 보이지 않는 항목을 가리키는 커서/선택 정리.
        let visible = Set(visibleNodes.map { $0.url })
        if let c = cursorURL, !visible.contains(c) { cursorURL = nil }
        markedURLs = markedURLs.filter { visible.contains($0) }
        objectWillChange.send()
    }

    /// 주어진 디렉터리 URL의 children을 (트리에 로드돼 있다면) 다시 스캔한다.
    private func rescanDirectory(_ dirURL: URL) {
        guard let root else { return }
        if dirURL == root.url {
            root.children = FileNode.scan(directory: root.url)
        } else if let dir = root.findNode(url: dirURL), dir.children != nil {
            dir.children = FileNode.scan(directory: dirURL)
        }
    }

    // MARK: - 드래그앤드롭 이동/복사

    /// sourceURL을 destDir(폴더)로 이동(또는 copy=true면 복사)한다.
    /// 성공하면 양쪽 폴더를 재스캔하고, 이동 시 열린 패널/상태의 경로를 갱신한다.
    @discardableResult
    func dropItem(_ sourceURL: URL, into destDir: URL, copy: Bool) -> Bool {
        let fm = FileManager.default

        // destDir이 실제 폴더인지 확인.
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: destDir.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        let sourceParent = sourceURL.deletingLastPathComponent()
        // 같은 폴더로의 이동은 무의미(복사는 허용).
        if !copy, sourceParent == destDir { return false }

        // 자기 자신 또는 자기 하위로의 이동/복사 방지.
        if destDir == sourceURL { return false }
        if destDir.path.hasPrefix(sourceURL.path + "/") { return false }

        // 목적지 이름 충돌 처리: 복사면 " 사본" 접미사, 이동이면 거부.
        var destination = destDir.appendingPathComponent(sourceURL.lastPathComponent)
        if fm.fileExists(atPath: destination.path) {
            if copy {
                destination = uniqueCopyURL(for: destination)
            } else {
                renameError = L(.existsInTarget(sourceURL.lastPathComponent))
                return false
            }
        }

        do {
            if copy {
                try fm.copyItem(at: sourceURL, to: destination)
            } else {
                try fm.moveItem(at: sourceURL, to: destination)
            }
        } catch {
            renameError = copy
                ? L(.copyFailed(error.localizedDescription))
                : L(.moveFailed(error.localizedDescription))
            return false
        }

        // 목적지 폴더의 children을 무조건 (재)로드하고 펼쳐서 결과를 보여준다.
        // 이미 펼쳐진 폴더로 드롭하면 expandedURLs가 안 바뀌어 갱신이 누락되므로
        // objectWillChange로 트리 재계산을 명시적으로 트리거한다.
        objectWillChange.send()
        if let destNode = (destDir == root?.url ? root : root?.findNode(url: destDir)) {
            destNode.children = FileNode.scan(directory: destDir)
        }
        expandedURLs.insert(destDir)

        if !copy {
            rescanDirectory(sourceParent)
            // 이동된 항목 관련 상태를 새 경로로 이전.
            migratePaths(from: sourceURL, to: destination)
        }
        persistOpenedFiles()
        return true
    }

    /// 중복 시 "이름 사본", "이름 사본 2" … 형태의 비어있는 URL을 찾는다.
    private func uniqueCopyURL(for url: URL) -> URL {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let copyWord = L(.copySuffix)
        var n = 1
        while true {
            let suffix = n == 1 ? copyWord : "\(copyWord) \(n)"
            let name = ext.isEmpty ? base + suffix : "\(base)\(suffix).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    /// 이동 시 펼침/커서/열린 패널의 URL 접두사를 old→new로 교체.
    private func migratePaths(from old: URL, to new: URL) {
        let oldPrefix = old.path
        func remap(_ url: URL) -> URL {
            if url == old { return new }
            if url.path.hasPrefix(oldPrefix + "/") {
                let suffix = String(url.path.dropFirst(oldPrefix.count))
                return URL(fileURLWithPath: new.path + suffix)
            }
            return url
        }
        expandedURLs = Set(expandedURLs.map(remap))
        if let c = cursorURL { cursorURL = remap(c) }
        for i in panels.indices {
            if let f = panels[i].fileURL { panels[i].fileURL = remap(f) }
        }
    }

    // MARK: - 패널 개수 조정

    var canAddPanel: Bool { panels.count < Self.maxPanels }
    var canRemovePanel: Bool { panels.count > 1 }

    /// 패널 추가(활성 패널 오른쪽에 빈 패널). 새 패널은 평균 폭으로.
    func addPanel() {
        guard canAddPanel else { return }
        let insertAt = activePanelIndex + 1
        panels.insert(ViewerPanel(), at: insertAt)
        let avg = panelWeights.reduce(0, +) / CGFloat(panelWeights.count)
        panelWeights.insert(avg, at: insertAt)
        activePanelIndex = insertAt
        persistOpenedFiles()
    }

    /// 새 뷰어 패널을 열고 그 패널에 파일을 연다(트리 Cmd+클릭용).
    /// 패널이 최대치라 더 못 늘리면 활성 패널에 연다. 폴더는 무시.
    func openInNewPanel(_ url: URL) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue { return }
        if canAddPanel { addPanel() }   // 새 패널(활성으로 전환됨), 최대치면 활성 패널 재사용
        openMarkdown(at: url, inPanel: activePanelIndex)
    }

    /// 두 패널의 위치를 맞바꾼다(헤더 드래그로 순서 교환). 폭 가중치도 함께 스왑.
    /// 활성/포커스는 드래그한 패널(source)을 따라 이동한다.
    func swapPanels(_ a: Int, _ b: Int) {
        guard a != b,
              panels.indices.contains(a), panels.indices.contains(b) else { return }
        panels.swapAt(a, b)
        if panelWeights.indices.contains(a), panelWeights.indices.contains(b) {
            panelWeights.swapAt(a, b)
        }
        // 드래그한 패널(a)이 b 자리로 이동 → 활성/포커스도 그 자리로.
        activePanelIndex = b
        focus = .panel(b)
        persistOpenedFiles()
    }

    /// 활성 패널 제거. 최소 1개 유지.
    func removeActivePanel() {
        removePanel(at: activePanelIndex)
    }

    /// 지정한 패널 제거. 최소 1개 유지. 활성 인덱스는 유효 범위로 보정.
    func removePanel(at index: Int) {
        guard canRemovePanel, panels.indices.contains(index) else { return }
        panels.remove(at: index)
        if panelWeights.indices.contains(index) { panelWeights.remove(at: index) }
        if index < activePanelIndex {
            activePanelIndex -= 1
        }
        activePanelIndex = min(activePanelIndex, panels.count - 1)
        normalizeWeights()
        persistOpenedFiles()
    }

    /// 패널 개수를 n으로 맞춘다(1~max). 늘리면 빈 패널 추가, 줄이면 뒤에서 제거.
    func setPanelCount(_ n: Int) {
        let target = min(max(n, 1), Self.maxPanels)
        while panels.count < target { panels.append(ViewerPanel()); panelWeights.append(1) }
        while panels.count > target { panels.removeLast(); panelWeights.removeLast() }
        activePanelIndex = min(activePanelIndex, panels.count - 1)
        normalizeWeights()
        persistOpenedFiles()
    }

    // MARK: - 패널 폭 조절

    /// index번째와 (index+1)번째 패널 사이 구분선을 dx만큼(전체폭 totalWidth 기준) 드래그.
    /// 두 패널의 가중치를 주고받되, 각 패널이 최소 비율 이하로 줄지 않도록 제한.
    func resizePanel(divider index: Int, by dx: CGFloat, totalWidth: CGFloat) {
        guard totalWidth > 0,
              panelWeights.indices.contains(index),
              panelWeights.indices.contains(index + 1) else { return }

        let sum = panelWeights.reduce(0, +)
        // dx(포인트)를 가중치 단위로 환산.
        let deltaWeight = dx / totalWidth * sum
        let minWeight = sum * (Self.minPanelFraction)

        var left = panelWeights[index] + deltaWeight
        var right = panelWeights[index + 1] - deltaWeight
        // 최소폭 보장: 한쪽이 한계에 닿으면 더 못 넘어가게 클램프.
        if left < minWeight {
            right -= (minWeight - left); left = minWeight
        }
        if right < minWeight {
            left -= (minWeight - right); right = minWeight
        }
        panelWeights[index] = left
        panelWeights[index + 1] = right
        persistWeights()
    }

    /// 패널 최소 폭(전체의 비율).
    private static let minPanelFraction: CGFloat = 0.15

    /// 가중치 배열을 panels 개수에 맞추고 합을 정규화.
    private func normalizeWeights() {
        if panelWeights.count != panels.count {
            panelWeights = Array(repeating: 1, count: panels.count)
        }
        let sum = panelWeights.reduce(0, +)
        if sum <= 0 { panelWeights = Array(repeating: 1, count: panels.count) }
    }

    // MARK: - 폰트 크기

    /// ⌘+ / ⌘- / ⌘0 이 적용될 영역.
    private enum FontTarget { case tree, viewer, terminal }

    /// 키보드 입력을 받는 곳을 기준으로 대상을 정한다.
    /// 터미널은 SwiftTerm이 first responder를 직접 가져가므로 `focus`에 잡히지 않아
    /// 응답자 사슬을 직접 확인한다.
    private var fontTarget: FontTarget {
        if terminalHasKeyboardFocus { return .terminal }
        return focus == .tree ? .tree : .viewer
    }

    /// 내장 터미널이 지금 키 입력을 받는 중인지.
    private var terminalHasKeyboardFocus: Bool {
        guard showTerminal,
              let window = NSApp.keyWindow,
              let responder = window.firstResponder as? NSView else { return false }
        var view: NSView? = responder
        while let current = view {
            if current is CommanderTerminalView { return true }
            view = current.superview
        }
        return false
    }

    /// ⌘+ / ⌘- / ⌘0 — **키보드 포커스가 있는 쪽**의 글자 크기를 바꾼다.
    /// 트리를 훑는 중이면 트리가, 문서를 읽는 중이면 본문이, 터미널에서 타이핑 중이면 터미널이 커진다.
    /// (뷰어 헤더의 폰트 버튼은 대상이 분명하므로 아래 뷰어 전용 메서드를 쓴다)
    func increaseFont() { stepFont(by: Self.fontStep) }
    func decreaseFont() { stepFont(by: -Self.fontStep) }

    func resetFont() {
        switch fontTarget {
        case .tree:     setTreeFont(Metrics.treeFontSize)
        case .viewer:   resetViewerFont()
        case .terminal: setTerminalFont(Metrics.terminalFontSize)
        }
    }

    private func stepFont(by delta: CGFloat) {
        switch fontTarget {
        case .tree:     setTreeFont(treeFontSize + delta)
        case .viewer:   setFont(viewerFontSize + delta)
        case .terminal: setTerminalFont(terminalFontSize + delta)
        }
    }

    /// 뷰어 본문 전용(헤더 버튼처럼 대상이 정해진 경로에서 쓴다).
    func increaseViewerFont() { setFont(viewerFontSize + Self.fontStep) }
    func decreaseViewerFont() { setFont(viewerFontSize - Self.fontStep) }
    func resetViewerFont()    { setFont(Self.defaultFontSize) }

    /// 터미널 전용(터미널 헤더 버튼용).
    func increaseTerminalFont() { setTerminalFont(terminalFontSize + Self.fontStep) }
    func decreaseTerminalFont() { setTerminalFont(terminalFontSize - Self.fontStep) }
    func resetTerminalFont()    { setTerminalFont(Metrics.terminalFontSize) }

    private func setFont(_ size: CGFloat) {
        viewerFontSize = min(max(size, Self.minFontSize), Self.maxFontSize)
    }

    private func setTreeFont(_ size: CGFloat) {
        treeFontSize = min(max(size, Self.minFontSize), Self.maxFontSize)
    }

    private func setTerminalFont(_ size: CGFloat) {
        terminalFontSize = min(max(size, Self.minFontSize), Self.maxFontSize)
    }

    /// ⌘+휠 처리. **마우스가 놓인 영역**의 글자 크기를 한 단계 조절한다.
    /// 처리했으면 true를 돌려준다(호출 측이 이벤트를 소비해야 함).
    ///
    /// PDF·이미지 패널은 자체 배율 로직(PannablePDFView·ImageViewer)이 있으므로
    /// false를 돌려 그쪽이 이벤트를 받게 둔다.
    func zoomHoveredArea(scrollingUp: Bool) -> Bool {
        let delta = scrollingUp ? Self.fontStep : -Self.fontStep
        switch hoverArea {
        case .tree:
            setTreeFont(treeFontSize + delta)
            return true
        case .terminal:
            setTerminalFont(terminalFontSize + delta)
            return true
        case .panel(let index):
            // PDF·이미지는 배율이, 서식 문서는 QuickLook이 크기를 담당한다.
            guard let panel = panels[safe: index],
                  !panel.isPDF, !panel.isImage, !panel.isRichDoc else { return false }
            setFont(viewerFontSize + delta)
            return true
        case .none:
            return false
        }
    }

    // MARK: - PDF 확대/축소

    static let minPDFZoom: CGFloat = 0.25
    static let maxPDFZoom: CGFloat = 6.0
    private static let pdfZoomStep: CGFloat = 0.25
    /// 명시적 배율이 아직 없을 때(폭 맞춤 모드) 확대/축소의 기준 배율.
    private static let pdfZoomBase: CGFloat = 1.0

    /// 이미지 배율 한계와 스텝(넓은 범위라 곱셈 방식).
    static let minImageZoom: CGFloat = 0.05
    static let maxImageZoom: CGFloat = 16.0
    private static let imageZoomFactor: CGFloat = 1.25

    /// PDF·이미지 패널의 확대/축소. sign>0이면 확대, <0이면 축소.
    /// 이미지는 곱셈(×1.25) 방식이며 맞춤 상태면 실제 맞춤 배율에서 시작한다.
    /// PDF는 기존 고정 스텝(±0.25) 방식 유지.
    private func adjustPDFZoom(panel index: Int, sign: CGFloat) {
        guard panels.indices.contains(index) else { return }
        let panel = panels[index]

        if panel.isImage {
            // 맞춤(pdfZoom==0) 상태면 뷰가 보고한 실제 배율에서 확대/축소를 시작.
            let current = panel.pdfZoom > 0 ? panel.pdfZoom : panel.imageFitScale
            let factor = sign > 0 ? Self.imageZoomFactor : 1 / Self.imageZoomFactor
            let next = min(max(current * factor, Self.minImageZoom), Self.maxImageZoom)
            panels[index].pdfZoom = next
            return
        }

        guard panel.showsPDF else { return }
        let current = panel.pdfZoom > 0 ? panel.pdfZoom : Self.pdfZoomBase
        let delta = sign > 0 ? Self.pdfZoomStep : -Self.pdfZoomStep
        let next = min(max(current + delta, Self.minPDFZoom), Self.maxPDFZoom)
        panels[index].pdfZoom = next
    }

    func pdfZoomIn(panel index: Int)  { adjustPDFZoom(panel: index, sign: 1) }
    func pdfZoomOut(panel index: Int) { adjustPDFZoom(panel: index, sign: -1) }

    /// 명시 배율로 설정(Cmd+휠 확대/축소용). 종류별 범위로 제한.
    func setPDFZoom(panel index: Int, to scale: CGFloat) {
        guard panels.indices.contains(index) else { return }
        if panels[index].isImage {
            panels[index].pdfZoom = min(max(scale, Self.minImageZoom), Self.maxImageZoom)
        } else if panels[index].showsPDF {
            panels[index].pdfZoom = min(max(scale, Self.minPDFZoom), Self.maxPDFZoom)
        }
    }

    /// 맞춤(autoScale)으로 복귀.
    func pdfZoomReset(panel index: Int) {
        guard panels.indices.contains(index) else { return }
        panels[index].pdfZoom = 0
    }

    /// 이미지 뷰가 맞춤 모드에서 실제 적용 중인 배율을 보고(헤더 % 표시용).
    /// 값이 바뀔 때만 반영해 불필요한 갱신을 막는다.
    func setImageFitScale(panel index: Int, to scale: CGFloat) {
        guard panels.indices.contains(index) else { return }
        guard abs(panels[index].imageFitScale - scale) > 0.0001 else { return }
        panels[index].imageFitScale = scale
    }

    /// PDF 뷰가 현재 보고 있는 쪽과 전체 쪽수를 보고(헤더 표시용).
    func setPDFPage(panel index: Int, page: Int, of count: Int) {
        guard panels.indices.contains(index) else { return }
        guard panels[index].pdfPage != page || panels[index].pdfPageCount != count else { return }
        panels[index].pdfPage = page
        panels[index].pdfPageCount = count
    }

    // MARK: - 세션 복원

    /// 앱 시작 시 호출: 저장된 폰트 크기, 루트 북마크, 마지막 파일을 복원한다.
    func restoreSession() {
        if defaults.object(forKey: Key.fontSize) != nil {
            setFont(CGFloat(defaults.double(forKey: Key.fontSize)))
        }

        if defaults.object(forKey: Key.treeFontSize) != nil {
            setTreeFont(CGFloat(defaults.double(forKey: Key.treeFontSize)))
        }

        if defaults.object(forKey: Key.terminalFontSize) != nil {
            setTerminalFont(CGFloat(defaults.double(forKey: Key.terminalFontSize)))
        }

        if defaults.object(forKey: Key.showTerminal) != nil {
            showTerminal = defaults.bool(forKey: Key.showTerminal)
        }

        if let raw = defaults.string(forKey: Key.terminalPosition),
           let saved = TerminalPosition(rawValue: raw) {
            terminalPosition = saved
        }

        // 패널 크기 복원. 저장값이 없으면 기본값을 그대로 쓴다.
        if defaults.object(forKey: Key.treeWidth) != nil {
            setTreeWidth(CGFloat(defaults.double(forKey: Key.treeWidth)))
        }
        if defaults.object(forKey: Key.terminalWidth) != nil {
            // 창 크기는 아직 모르므로 상한은 넉넉히 두고, 실제 제한은 레이아웃이 건다.
            setTerminalWidth(CGFloat(defaults.double(forKey: Key.terminalWidth)), limit: .greatestFiniteMagnitude)
        }
        if defaults.object(forKey: Key.terminalHeight) != nil {
            setTerminalHeight(CGFloat(defaults.double(forKey: Key.terminalHeight)), limit: .greatestFiniteMagnitude)
        }

        // 파일 필터·정렬 복원 — 루트 로드(스캔) 전에 적용해야 첫 스캔부터 반영된다.
        // 루트가 아직 없으므로 didSet의 rescanAll은 무해하게 빠진다.
        if defaults.object(forKey: Key.showAllFiles) != nil {
            let saved = defaults.bool(forKey: Key.showAllFiles)
            FileNode.showAllFiles = saved
            showAllFiles = saved
        }
        if let rawField = defaults.string(forKey: Key.sortField),
           let field = SortField(rawValue: rawField) {
            let ascending = defaults.object(forKey: Key.sortAscending) as? Bool
                ?? field.defaultAscending
            let saved = SortOrder(field: field, ascending: ascending)
            FileNode.sortOrder = saved
            sortOrder = saved
        }

        loadRecentFolders()

        // 첫 실행이면 복원할 것이 없다. 환영 화면이 뜬다(실패가 아니므로 안내도 없다).
        guard let data = defaults.data(forKey: Key.rootBookmark) else { return }

        // 아래 복원 실패들은 예전에는 조용히 빠져나가 빈 화면만 남겼다.
        // 폴더가 지워졌거나 옮겨졌거나 권한을 잃은 것이니 사용자에게 알려야 한다.
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            restoreFailure = RestoreFailure(path: recentFolders.first?.path)
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            restoreFailure = RestoreFailure(path: url.path)
            return
        }
        accessedRootURL = url

        // 북마크는 풀렸지만 폴더 자체가 사라진 경우(외장 디스크 분리 등).
        guard FileManager.default.fileExists(atPath: url.path) else {
            stopAccessingRoot()
            restoreFailure = RestoreFailure(path: url.path)
            return
        }

        let node = FileNode(url: url, isDirectory: true)
        node.loadChildrenIfNeeded()
        root = node

        if isStale { saveRootBookmark(url) }  // 북마크 갱신

        restoreOpenedFiles(under: node)
    }

    /// 저장된 패널별 파일들을 복원한다(각 패널에 해당 파일을 열고, 경로를 따라 트리 펼침).
    private func restoreOpenedFiles(under root: FileNode) {
        guard let paths = defaults.array(forKey: Key.openedFiles) as? [String],
              !paths.isEmpty else { return }

        var restored: [ViewerPanel] = []
        for path in paths {
            guard !path.isEmpty else { restored.append(ViewerPanel()); continue }
            let target = URL(fileURLWithPath: path)
            guard target.path.hasPrefix(root.url.path) else {
                restored.append(ViewerPanel()); continue
            }
            expandPath(to: target, from: root)
            if root.findNode(url: target) != nil {
                let ext = target.pathExtension.lowercased()
                let isMd = FileNode.markdownExtensions.contains(ext)
                let isPdf = FileNode.pdfExtensions.contains(ext)
                let isImg = FileNode.imageExtensions.contains(ext)
                let isHtml = FileNode.htmlExtensions.contains(ext)
                let isRich = FileNode.richDocExtensions.contains(ext)
                let isBinary = isPdf || isImg || isRich
                let text = isBinary ? nil : ((try? String(contentsOf: target, encoding: .utf8)) ?? L(.cannotReadFile))
                restored.append(ViewerPanel(fileURL: target, content: text,
                                            isPlainText: !isMd && !isBinary && !isHtml,
                                            isPDF: isPdf, isImage: isImg,
                                            isHTML: isHtml, isRichDoc: isRich,
                                            richDocPDF: isRich ? DocumentConverter.cachedPDF(for: target) : nil))
            } else {
                restored.append(ViewerPanel())
            }
        }

        if !restored.isEmpty {
            panels = Array(restored.prefix(Self.maxPanels))
            let savedActive = defaults.integer(forKey: Key.activePanel)
            activePanelIndex = min(max(savedActive, 0), panels.count - 1)
            // 폭 비율 복원(개수 불일치 시 균등).
            if let saved = defaults.array(forKey: Key.panelWeights) as? [Double],
               saved.count == panels.count {
                panelWeights = saved.map { CGFloat($0) }
            } else {
                panelWeights = Array(repeating: 1, count: panels.count)
            }
            normalizeWeights()
            // 커서를 활성 패널의 파일에 맞춘다.
            cursorURL = panels[activePanelIndex].fileURL ?? root.children?.first?.url
            // 복원된 서식 문서 중 아직 변환본이 없는 것은 뒤에서 변환해 둔다.
            for index in panels.indices { startConversionIfNeeded(panel: index) }
        }
    }

    /// target에 이르는 중간 폴더들의 children을 로드하고, target의 부모까지의
    /// 모든 폴더를 펼침 상태로 기록한다.
    private func expandPath(to target: URL, from root: FileNode) {
        var current = root
        let rootComponents = root.url.pathComponents
        let targetComponents = target.pathComponents
        guard targetComponents.count > rootComponents.count else { return }

        let pathComps = Array(targetComponents[rootComponents.count...])
        for (offset, component) in pathComps.enumerated() {
            current.loadChildrenIfNeeded()
            guard let next = current.children?.first(where: { $0.name == component }) else { return }
            // target의 부모까지(즉 마지막 직전 컴포넌트까지)인 폴더만 펼친다.
            let isParentLevel = offset < pathComps.count - 1
            if isParentLevel, next.isDirectory {
                expandedURLs.insert(next.url)
            }
            current = next
        }
    }

    // MARK: - 북마크 / 정리

    /// 현재 패널들의 파일 경로와 활성 인덱스, 폭 비율을 저장.
    private func persistOpenedFiles() {
        let paths = panels.map { $0.fileURL?.path ?? "" }
        defaults.set(paths, forKey: Key.openedFiles)
        defaults.set(activePanelIndex, forKey: Key.activePanel)
        persistWeights()
    }

    private func persistWeights() {
        defaults.set(panelWeights.map { Double($0) }, forKey: Key.panelWeights)
    }

    private func saveRootBookmark(_ url: URL) {
        if let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(data, forKey: Key.rootBookmark)
        }
    }

    private func stopAccessingRoot() {
        accessedRootURL?.stopAccessingSecurityScopedResource()
        accessedRootURL = nil
    }

    // MARK: - 외부 변경 감시 (FSEvents)

    /// 현재 루트에 대한 파일시스템 감시를 (재)시작한다. root의 didSet에서 호출.
    private func startWatchingRoot() {
        directoryWatcher = nil
        guard let rootURL = root?.url else { return }
        directoryWatcher = DirectoryWatcher(url: rootURL) { [weak self] in
            self?.handleExternalChange()
        }
    }

    /// 외부에서 파일시스템이 바뀌었을 때 호출(FSEvents 콜백, 메인 큐).
    /// 로드된 모든 폴더를 다시 스캔해 트리를 실제 디스크 상태와 맞추고,
    /// 열린 뷰어 패널의 파일 내용도 디스크에서 다시 읽어 반영한다.
    private func handleExternalChange() {
        // 인라인 이름 편집 중에는 재스캔이 편집 대상 노드를 교체해 버릴 수 있어
        // 건너뛴다. 편집이 끝나면 다음 이벤트에서 반영된다.
        guard renamingURL == nil else { return }
        rescanAll()
        reloadOpenPanelsFromDisk()
        // 파일 인덱스는 여기서 다시 훑지 않고 낡았다고만 표시한다. 파일 하나 저장할 때마다
        // 수만 개를 다시 훑을 이유가 없다. 검색 창을 열 때 필요하면 그때 갱신한다.
        fileIndex.markStale()
    }

    /// 열린 각 패널의 파일을 디스크에서 다시 읽어 내용이 바뀌었으면 갱신한다.
    /// - 편집 중(isEditing)인 패널은 사용자 작업을 덮어쓰지 않도록 건너뛴다.
    /// - PDF는 content를 쓰지 않으므로 PDFViewer가 URL 기준으로 다시 그리도록 파일만 확인.
    /// - 파일이 삭제됐으면 그대로 두어(트리 재스캔이 이미 반영) 마지막 내용을 유지한다.
    private func reloadOpenPanelsFromDisk() {
        for index in panels.indices {
            let panel = panels[index]
            guard let url = panel.fileURL else { continue }
            // 편집 중이면 손대지 않는다(저장 안 된 변경 보호).
            if panel.isEditing { continue }
            // 파일이 사라졌으면 마지막으로 읽은 내용을 유지.
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            // PDF·이미지·서식 문서는 텍스트로 읽지 않는다. 전용 뷰가 파일 변경을 자체 반영한다.
            if panel.isPDF || panel.isImage || panel.isRichDoc { continue }
            guard let latest = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // 내용이 실제로 바뀌었을 때만 교체해 불필요한 재렌더를 막는다.
            if latest != panel.content {
                panels[index].content = latest
            }
        }
    }

    deinit {
        accessedRootURL?.stopAccessingSecurityScopedResource()
    }
}

extension Array {
    /// 범위를 벗어나면 nil을 반환하는 안전한 인덱스 접근.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
