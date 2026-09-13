import Foundation

/// 파일 트리 창 하나의 상태.
///
/// Total Commander의 좌·우 패널처럼 트리마다 루트 폴더·펼침·커서·다중 선택이 따로 있다.
/// 파일시스템을 바꾸는 작업(복사·이동·삭제·이름 변경)과 뷰어·세션은 `WorkspaceStore`가 맡고,
/// 이 타입은 "이 트리가 무엇을 어떻게 보여 주고 있는가"만 책임진다.
@MainActor
final class TreePane: ObservableObject, Identifiable {
    let id = UUID()

    /// 루트 폴더 노드(없으면 폴더 미선택 상태).
    @Published var root: FileNode? {
        didSet {
            guard oldValue?.url != root?.url else { return }
            startWatching()
        }
    }
    /// 펼쳐진 폴더 URL 집합(트리 펼침 상태의 단일 출처).
    @Published var expandedURLs: Set<URL> = []
    /// 키보드 탐색 커서가 가리키는 노드 URL.
    @Published var cursorURL: URL?
    /// 다중 선택된 노드 URL 집합(Total Commander 스타일, Space/Insert로 토글).
    /// 커서(cursorURL)와는 독립적. 비어 있으면 단일 선택 모드(커서 항목만 대상).
    @Published var markedURLs: Set<URL> = []

    /// 루트 하위에서 외부(Finder 등) 변경이 감지되면 메인 큐에서 호출된다.
    var onExternalChange: ((TreePane) -> Void)?

    /// 루트 하위 트리의 외부 변경 감시자.
    private var directoryWatcher: DirectoryWatcher?
    /// 보안 스코프 접근을 유지 중인 루트 URL(stop을 위해 보관).
    private var accessedRootURL: URL?

    // MARK: - 루트 설정

    /// 폴더를 이 트리의 새 루트로 삼는다. 펼침·선택은 비우고 커서는 첫 항목에 둔다.
    func setRoot(_ url: URL) {
        let node = FileNode(url: url, isDirectory: true)
        node.loadChildrenIfNeeded()
        root = node
        expandedURLs = []
        markedURLs = []
        cursorURL = node.children?.first?.url
    }

    /// 루트가 파일시스템 최상위("/")가 아니면 상위로 올라갈 수 있다.
    var canGoToParent: Bool {
        guard let current = root else { return false }
        return current.url.deletingLastPathComponent() != current.url
    }

    /// url이 이 트리의 루트이거나 그 하위인지.
    func contains(_ url: URL) -> Bool {
        guard let rootPath = root?.url.path else { return false }
        return url.path == rootPath || url.path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    // MARK: - 보안 스코프 접근

    /// url에 대한 보안 스코프 접근을 시작한다. 이전 접근은 먼저 놓는다.
    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        stopAccessing()
        guard url.startAccessingSecurityScopedResource() else { return false }
        accessedRootURL = url
        return true
    }

    func stopAccessing() {
        accessedRootURL?.stopAccessingSecurityScopedResource()
        accessedRootURL = nil
    }

    // MARK: - 노드 조회

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

    func node(for url: URL?) -> FileNode? {
        guard let url, let root else { return nil }
        return root.findNode(url: url)
    }

    /// 노드의 부모 노드. 루트 직계면 nil.
    func parentNode(of target: FileNode) -> FileNode? {
        guard let root else { return nil }
        let parentURL = target.url.deletingLastPathComponent()
        if parentURL == root.url { return nil }
        return root.findNode(url: parentURL)
    }

    /// 작업(복사/삭제 등) 대상 URL 목록.
    /// 선택된 항목이 있으면 그 전체, 없으면 커서 항목 1개.
    /// 트리 표시 순서(visibleNodes)를 따라 안정적으로 정렬해 반환한다.
    var actionTargetURLs: [URL] {
        if !markedURLs.isEmpty {
            return visibleNodes.map { $0.url }.filter { markedURLs.contains($0) }
        }
        if let c = cursorURL { return [c] }
        return []
    }

    /// F5·F6에서 이 트리가 받는 쪽일 때 받을 폴더.
    ///
    /// 커서가 폴더면 그 폴더, 파일이면 그 파일이 든 폴더. 커서가 없으면 루트.
    /// 펼침 여부는 보지 않는다. 폴더를 클릭하면 펼침이 토글되므로, 이미 펼친 폴더를 받을 곳으로
    /// 고르면 접히면서 엉뚱하게 그 상위 폴더로 보내게 된다.
    var transferTargetDirectory: URL? {
        guard let root else { return nil }
        guard let cursor = node(for: cursorURL) else { return root.url }
        return cursor.isDirectory ? cursor.url : cursor.url.deletingLastPathComponent()
    }

    // MARK: - 펼침 / 커서 드러내기

    /// target에 이르는 중간 폴더들의 children을 로드하고, target의 부모까지의
    /// 모든 폴더를 펼침 상태로 기록한다.
    func expandPath(to target: URL) {
        guard var current = root else { return }
        let rootComponents = current.url.pathComponents
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

    /// 주어진 파일 위치를 드러낸다: 경로상의 폴더를 펼치고 커서를 그 파일로.
    /// 이 트리 루트 밖이면 아무것도 하지 않는다.
    func reveal(_ url: URL) {
        guard let root, url.path.hasPrefix(root.url.path) else { return }
        expandPath(to: url)
        cursorURL = url
    }

    // MARK: - 재스캔 / 경로 갱신

    /// 루트와 현재 로드된 모든 폴더를 재스캔한다(필터 변경·외부 변경 등 전역 갱신용).
    ///
    /// scan()이 만드는 새 자식 노드는 children == nil(미로드)이므로, 재귀 시
    /// "원래 로드돼 있었는지"를 부모에서 판단해 넘긴다. 그래야 펼쳐져 있던
    /// 하위 폴더가 재스캔 뒤에도 children을 다시 채워 펼침 상태를 유지한다.
    func rescanAll() {
        guard let root else { return }
        if root.children != nil { reload(root) }
        // 더 이상 보이지 않는 항목을 가리키는 커서/선택 정리.
        let visible = Set(visibleNodes.map { $0.url })
        if let c = cursorURL, !visible.contains(c) { cursorURL = nil }
        markedURLs = markedURLs.filter { visible.contains($0) }
        objectWillChange.send()
    }

    /// 주어진 디렉터리 URL의 children을 (이 트리에 로드돼 있다면) 다시 스캔한다.
    func rescanDirectory(_ dirURL: URL) {
        guard let dir = loadedDirectory(atPath: dirURL.path), dir.children != nil else { return }
        reload(dir)
    }

    /// 폴더를 다시 스캔하되, 그 아래 펼쳐져 있던 폴더도 이어서 다시 읽는다.
    ///
    /// scan()이 만드는 새 자식 노드는 children == nil(미로드)이라, 여기서 멈추면 펼쳐 둔
    /// 하위 폴더가 접힌 것처럼 비어 보인다(파일 감시가 잠시 뒤 다시 채울 때까지 깜빡인다).
    private func reload(_ node: FileNode) {
        node.children = FileNode.scan(directory: node.url)
        for child in node.children ?? [] where child.isDirectory && expandedURLs.contains(child.url) {
            reload(child)
        }
    }

    /// 이미 로드된 노드 중에서 경로가 같은 폴더를 찾는다(루트 포함).
    ///
    /// URL끼리 ==로 비교하지 않고 경로 문자열로 비교한다. 폴더 URL은 만든 방법에 따라
    /// 끝에 "/"가 붙기도 하고 안 붙기도 해서(`deletingLastPathComponent`는 붙이고,
    /// 사용자가 입력한 경로는 안 붙는다) ==로는 같은 폴더를 놓친다.
    func loadedDirectory(atPath path: String) -> FileNode? {
        guard let root else { return nil }
        // URL.path는 끝의 "/"를 떼지만, 문자열로 들어온 경로에는 붙어 있을 수 있다.
        let normalized = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        func search(_ node: FileNode) -> FileNode? {
            if node.url.path == normalized { return node }
            guard node.isDirectory, let children = node.children,
                  normalized.hasPrefix(node.url.path + "/") || node.url.path == "/" else { return nil }
            for child in children where child.isDirectory {
                if let hit = search(child) { return hit }
            }
            return nil
        }
        return search(root)
    }

    /// 이동·이름 변경 뒤 펼침/커서/선택의 URL 접두사를 old→new로 교체.
    func migratePaths(from old: URL, to new: URL) {
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
        markedURLs = Set(markedURLs.map(remap))
        if let c = cursorURL { cursorURL = remap(c) }
    }

    /// 삭제된 경로(및 그 하위)를 가리키는 펼침/커서/선택을 지운다.
    func forget(deleted: [URL]) {
        func affected(_ u: URL) -> Bool {
            deleted.contains { u == $0 || u.path.hasPrefix($0.path + "/") }
        }
        expandedURLs = expandedURLs.filter { !affected($0) }
        markedURLs = markedURLs.filter { !affected($0) }
        if let c = cursorURL, affected(c) { cursorURL = nil }
    }

    // MARK: - 외부 변경 감시 (FSEvents)

    /// 현재 루트에 대한 파일시스템 감시를 (재)시작한다. root의 didSet에서 호출.
    private func startWatching() {
        directoryWatcher = nil
        guard let rootURL = root?.url else { return }
        directoryWatcher = DirectoryWatcher(url: rootURL) { [weak self] in
            guard let self else { return }
            self.onExternalChange?(self)
        }
    }

    deinit {
        accessedRootURL?.stopAccessingSecurityScopedResource()
    }
}
