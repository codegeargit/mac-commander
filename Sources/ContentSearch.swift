import Foundation

/// 본문 검색 결과 한 줄.
struct ContentMatch: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    /// 1부터 시작하는 줄 번호.
    let lineNumber: Int
    /// 표시용으로 다듬은 줄 내용(앞 공백 제거, 길면 잘림).
    let line: String
}

/// 루트 폴더 하위 문서들의 본문을 훑어 검색어가 있는 줄을 찾는다.
///
/// 파일 목록은 `FileIndex`가 만든 것을 그대로 쓴다. 읽기는 백그라운드에서 배치로 돌리고
/// 배치마다 결과를 화면에 붙여, 큰 폴더에서도 첫 결과를 곧바로 볼 수 있게 한다.
@MainActor
final class ContentSearch: ObservableObject {
    /// 화면에 담을 최대 결과 수. 넘으면 잘렸음을 알린다.
    static let maxMatches = 400
    /// 파일 하나에서 가져올 최대 줄 수. 한 파일이 결과를 다 차지하지 않게 한다.
    static let maxPerFile = 5
    /// 이보다 큰 파일은 건너뛴다(대용량 로그를 훑다 멈춰 있는 것처럼 보이는 걸 막는다).
    static let maxFileSize = 5 * 1024 * 1024
    /// 한 배치에서 읽을 파일 수. 배치 사이에 메인 스레드가 화면을 갱신한다.
    private static let batchSize = 80
    /// 표시용 줄 길이 상한.
    private static let maxLineLength = 240

    @Published private(set) var matches: [ContentMatch] = []
    @Published private(set) var isSearching = false
    /// 결과 상한에 걸려 도중에 멈췄는지.
    @Published private(set) var truncated = false
    /// 마지막으로 검색을 마친 문자열(결과 표시 문맥).
    @Published private(set) var completedQuery = ""

    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
        isSearching = false
    }

    func clear() {
        cancel()
        matches = []
        truncated = false
        completedQuery = ""
    }

    /// 검색을 시작한다. 이미 돌고 있던 검색은 취소된다.
    func run(query: String, in urls: [URL]) {
        cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        matches = []
        truncated = false
        completedQuery = trimmed
        guard !trimmed.isEmpty else { return }

        isSearching = true
        task = Task { [weak self] in
            for chunk in stride(from: 0, to: urls.count, by: Self.batchSize) {
                if Task.isCancelled { break }
                let slice = Array(urls[chunk..<min(chunk + Self.batchSize, urls.count)])
                let hits = await Task.detached(priority: .utility) {
                    slice.flatMap { Self.search(query: trimmed, in: $0) }
                }.value

                if Task.isCancelled { break }
                guard let self else { return }
                self.matches.append(contentsOf: hits)
                if self.matches.count >= Self.maxMatches {
                    self.matches = Array(self.matches.prefix(Self.maxMatches))
                    self.truncated = true
                    break
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.isSearching = false
        }
    }

    /// 파일 하나를 훑어 검색어가 있는 줄을 모은다(백그라운드에서 호출).
    private nonisolated static func search(query: String, in url: URL) -> [ContentMatch] {
        let ext = url.pathExtension.lowercased()
        // 바이너리는 텍스트로 읽을 수 없다. PDF·Word 본문 검색은 열어 놓고 ⌘F로 한다.
        // (.docx는 zip이라 그대로 읽으면 깨진 바이트가 결과로 올라온다.)
        if FileNode.pdfExtensions.contains(ext) || FileNode.imageExtensions.contains(ext)
            || FileNode.richDocExtensions.contains(ext) {
            return []
        }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize, size <= maxFileSize else { return [] }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var found: [ContentMatch] = []
        var lineNumber = 0
        text.enumerateLines { line, stop in
            lineNumber += 1
            guard line.range(of: query, options: .caseInsensitive) != nil else { return }
            found.append(ContentMatch(url: url, lineNumber: lineNumber, line: trim(line)))
            if found.count >= maxPerFile { stop = true }
        }
        return found
    }

    /// 들여쓰기를 없애고 너무 긴 줄은 잘라 한 줄로 보여줄 수 있게 만든다.
    private nonisolated static func trim(_ line: String) -> String {
        let squeezed = line.trimmingCharacters(in: .whitespaces)
        guard squeezed.count > maxLineLength else { return squeezed }
        return String(squeezed.prefix(maxLineLength)) + "…"
    }
}
