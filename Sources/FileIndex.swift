import Foundation

/// 루트 폴더 하위 전체 파일 목록 인덱스.
///
/// 트리는 폴더를 펼칠 때 lazy하게 스캔하므로 아직 펼치지 않은 곳의 파일을 모른다.
/// 검색은 펼침 상태와 무관해야 하니 전체를 따로 한 번 훑어 둔다.
/// 빠른 열기(⌘P)와 폴더 전체 본문 검색이 이 인덱스를 함께 쓴다.
@MainActor
final class FileIndex: ObservableObject {
    /// 인덱스에 담을 최대 파일 수. 아주 큰 트리에서 시간·메모리가 폭주하는 걸 막는다.
    static let maxEntries = 30_000

    /// 인덱싱된 파일들(경로 순).
    private(set) var entries: [URL] = []
    /// 상한에 걸려 일부만 담겼는지. 검색 결과가 전부가 아님을 사용자에게 알리는 데 쓴다.
    private(set) var truncated = false

    /// 스캔이 돌고 있는지(검색 창에서 "훑는 중" 표시).
    @Published private(set) var isScanning = false
    /// 인덱스가 갱신될 때마다 올라가는 값. 뷰가 결과를 다시 계산하는 신호로 쓴다.
    @Published private(set) var revision = 0

    /// 어떤 조건으로 인덱싱했는지. 루트나 필터가 바뀌면 다시 훑어야 한다.
    private var indexedRoot: URL?
    private var indexedShowAllFiles = false
    /// 파일시스템이 바뀐 뒤로 다시 훑지 않았는지.
    private var isStale = true
    private var scanTask: Task<Void, Never>?

    /// 파일시스템 변경을 감지했을 때 호출. 곧바로 다시 훑지 않고 표시만 해 둔다.
    /// (파일 하나 저장할 때마다 수만 개를 다시 훑을 이유가 없다)
    func markStale() { isStale = true }

    /// 검색 창을 열 때 호출. 인덱스가 없거나 낡았으면 백그라운드로 다시 훑는다.
    func refreshIfNeeded(root: URL?, showAllFiles: Bool) {
        guard let root else {
            scanTask?.cancel()
            entries = []
            truncated = false
            indexedRoot = nil
            isStale = true
            revision += 1
            return
        }
        let changedScope = (indexedRoot != root) || (indexedShowAllFiles != showAllFiles)
        guard changedScope || isStale else { return }

        scanTask?.cancel()
        indexedRoot = root
        indexedShowAllFiles = showAllFiles
        isStale = false
        isScanning = true
        // 큰 폴더에서 UI가 멈추지 않게 스캔은 백그라운드에서 돌린다.
        scanTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Self.collect(root: root, showAllFiles: showAllFiles)
            }.value
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.entries = result.urls
            self.truncated = result.truncated
            self.isScanning = false
            self.revision += 1
        }
    }

    /// 검색어와 일치하는 파일을 점수순으로 돌려준다.
    ///
    /// 공백으로 나눈 토큰이 **모두** 들어 있어야 한다(`design token` → 둘 다 포함).
    /// 파일명 일치를 경로 일치보다 높게 본다.
    func matches(_ query: String, limit: Int = 60) -> [URL] {
        let tokens = query.lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard !tokens.isEmpty else { return [] }
        let rootPath = indexedRoot?.path ?? ""

        var scored: [(url: URL, score: Int)] = []
        for url in entries {
            guard let score = Self.score(for: url, tokens: tokens, rootPath: rootPath) else { continue }
            scored.append((url, score))
        }
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            // 동점이면 얕은 경로 → 이름순. 가까운 파일이 위로 온다.
            let depthA = a.url.pathComponents.count
            let depthB = b.url.pathComponents.count
            if depthA != depthB { return depthA < depthB }
            return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
        return scored.prefix(limit).map(\.url)
    }

    /// 토큰별 점수 합. 하나라도 어디에도 없으면 nil(제외).
    private static func score(for url: URL, tokens: [String], rootPath: String) -> Int? {
        let name = url.lastPathComponent.lowercased()
        let relative = url.path.hasPrefix(rootPath)
            ? String(url.path.dropFirst(rootPath.count)).lowercased()
            : url.path.lowercased()

        var total = 0
        for token in tokens {
            if name.hasPrefix(token) {
                total += 4
            } else if name.contains(token) {
                total += 3
            } else if relative.contains(token) {
                total += 1
            } else {
                return nil
            }
        }
        return total
    }

    /// 루트 하위를 훑어 파일 목록을 만든다(백그라운드에서 호출).
    /// 표시 필터를 트리와 똑같이 적용해, 트리에 안 보이는 파일이 검색에만 나오는 일이 없게 한다.
    private nonisolated static func collect(root: URL, showAllFiles: Bool) -> (urls: [URL], truncated: Bool) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return ([], false) }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { return (urls, false) }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard showAllFiles
                    || FileNode.defaultVisibleExtensions.contains(url.pathExtension.lowercased())
            else { continue }

            urls.append(url)
            if urls.count >= maxEntries { return (urls, true) }
        }
        return (urls, false)
    }
}
