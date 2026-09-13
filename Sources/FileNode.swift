import Foundation

/// 트리 정렬 기준.
enum SortField: String, CaseIterable, Identifiable {
    case name, modified, size

    var id: String { rawValue }

    /// 기준을 바꿀 때 함께 적용할 기본 방향.
    /// 날짜와 크기는 큰 값(최신·큰 파일)을 먼저 보는 쪽이 자연스럽다.
    var defaultAscending: Bool { self == .name }
}

/// 정렬 기준 + 방향.
struct SortOrder: Equatable {
    var field: SortField = .name
    var ascending: Bool = true
}

/// 파일 트리의 한 노드. 실제 파일 시스템의 폴더 또는 마크다운 파일을 가리킨다.
///
/// 폴더의 children은 처음 펼칠 때 lazy하게 로드한다(큰 트리 대응).
final class FileNode: Identifiable, ObservableObject {
    let id: URL          // 파일 URL을 안정적인 식별자로 사용
    let url: URL
    let name: String
    let isDirectory: Bool
    /// 정렬에 쓰는 수정 시각. 스캔할 때 함께 읽어 둔다(정렬마다 디스크를 다시 묻지 않게).
    let modifiedAt: Date
    /// 정렬에 쓰는 파일 크기(바이트). 폴더는 0.
    let size: Int64

    /// 폴더의 하위 노드. nil이면 아직 스캔 전.
    @Published var children: [FileNode]?

    init(url: URL, isDirectory: Bool, modifiedAt: Date = .distantPast, size: Int64 = 0) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.modifiedAt = modifiedAt
        self.size = size
    }

    /// 마크다운으로 취급할 확장자.
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    /// PDF로 취급할 확장자.
    static let pdfExtensions: Set<String> = ["pdf"]

    /// HTML로 취급할 확장자(WebView로 그대로 렌더링).
    static let htmlExtensions: Set<String> = ["html", "htm"]

    /// 서식 문서로 취급할 확장자(QuickLook이 Finder 미리보기와 같은 품질로 렌더링).
    /// Office 문서와 Apple iWork 문서를 함께 다룬다.
    static let richDocExtensions: Set<String> = [
        "docx", "doc", "rtf", "rtfd",
        "xlsx", "xls", "pptx", "ppt",
        "pages", "numbers", "key",
    ]

    /// 이미지로 취급할 확장자(NSImage가 여는 일반 포맷).
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif",
        "heic", "heif", "webp", "svg", "ico", "icns",
    ]

    /// 필터가 꺼져 있어도(마크다운만 모드) 트리에 기본 표시하는 확장자.
    /// 마크다운 + PDF + 이미지 + HTML + 서식 문서. 뷰어가 렌더링할 수 있는 파일들.
    static let defaultVisibleExtensions: Set<String> =
        markdownExtensions
            .union(pdfExtensions)
            .union(imageExtensions)
            .union(htmlExtensions)
            .union(richDocExtensions)

    /// 전체 파일을 트리에 표시할지(false면 마크다운·PDF만). 스캔 시 참조하는 전역 플래그.
    /// WorkspaceStore.showAllFiles가 이 값을 갱신한다.
    static var showAllFiles: Bool = false

    /// 트리 정렬 기준. 스캔 시 참조하는 전역 플래그(WorkspaceStore.sortOrder가 갱신).
    static var sortOrder: SortOrder = SortOrder()

    var isMarkdown: Bool {
        !isDirectory && FileNode.markdownExtensions.contains(url.pathExtension.lowercased())
    }

    var isPDF: Bool {
        !isDirectory && FileNode.pdfExtensions.contains(url.pathExtension.lowercased())
    }

    var isImage: Bool {
        !isDirectory && FileNode.imageExtensions.contains(url.pathExtension.lowercased())
    }

    var isHTML: Bool {
        !isDirectory && FileNode.htmlExtensions.contains(url.pathExtension.lowercased())
    }

    var isRichDoc: Bool {
        !isDirectory && FileNode.richDocExtensions.contains(url.pathExtension.lowercased())
    }

    /// 뷰어가 전용 렌더링을 제공하는 파일(마크다운·PDF·이미지·HTML·서식 문서).
    /// 커서 이동 시 자동 미리보기 대상.
    var isViewable: Bool { isMarkdown || isPDF || isImage || isHTML || isRichDoc }

    /// 하위 노드를 (아직 로드하지 않았다면) 스캔해 채운다.
    func loadChildrenIfNeeded() {
        guard isDirectory, children == nil else { return }
        children = FileNode.scan(directory: url)
    }

    /// 디렉터리를 한 단계 스캔: 하위 폴더 + (필터에 맞는) 파일, 현재 정렬 기준으로.
    /// Commander 관례대로 폴더가 먼저, 그다음 파일이다(정렬 기준과 무관하게 유지).
    static func scan(directory: URL) -> [FileNode] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isRegularFileKey, .isPackageKey,
            .contentModificationDateKey, .fileSizeKey,
        ]
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var folders: [FileNode] = []
        var files: [FileNode] = []

        for url in entries {
            let values = try? url.resourceValues(forKeys: Set(keys))
            // .pages·.rtfd 같은 문서는 실제로는 폴더(패키지)지만 사용자에게는 파일 하나다.
            // 뷰어가 여는 형식이면 펼치지 않고 파일로 다룬다.
            let isPackageDoc = (values?.isPackage ?? false)
                && richDocExtensions.contains(url.pathExtension.lowercased())
            let isDir = (values?.isDirectory ?? false) && !isPackageDoc
            let modified = values?.contentModificationDate ?? .distantPast
            if isDir {
                folders.append(FileNode(url: url, isDirectory: true, modifiedAt: modified))
            } else if showAllFiles || defaultVisibleExtensions.contains(url.pathExtension.lowercased()) {
                // 기본은 뷰어가 렌더할 수 있는 형식만. showAllFiles면 모든 파일 표시.
                files.append(FileNode(url: url, isDirectory: false, modifiedAt: modified,
                                      size: Int64(values?.fileSize ?? 0)))
            }
        }

        let comparator = Self.comparator(for: sortOrder)
        return folders.sorted(by: comparator) + files.sorted(by: comparator)
    }

    /// 정렬 기준에 맞는 비교자. 같은 값이면 이름순으로 갈라 순서가 흔들리지 않게 한다.
    static func comparator(for order: SortOrder) -> (FileNode, FileNode) -> Bool {
        let byName: (FileNode, FileNode) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        switch order.field {
        case .name:
            return order.ascending ? byName : { byName($1, $0) }
        case .modified:
            return { a, b in
                guard a.modifiedAt != b.modifiedAt else { return byName(a, b) }
                return order.ascending ? a.modifiedAt < b.modifiedAt : a.modifiedAt > b.modifiedAt
            }
        case .size:
            return { a, b in
                guard a.size != b.size else { return byName(a, b) }
                return order.ascending ? a.size < b.size : a.size > b.size
            }
        }
    }

    /// 트리 전체에서 주어진 URL의 노드를 찾는다(이미 로드된 범위 내).
    func findNode(url target: URL) -> FileNode? {
        if url == target { return self }
        guard let children else { return nil }
        for child in children {
            if let hit = child.findNode(url: target) { return hit }
        }
        return nil
    }
}
