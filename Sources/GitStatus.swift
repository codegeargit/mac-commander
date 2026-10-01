import Foundation

/// 트리에 표시하는 파일 하나의 git 상태.
enum GitFileStatus: Int, Comparable {
    // 값이 클수록 강한 상태. 폴더는 안쪽 항목 중 가장 강한 상태로 칠한다.
    case untracked = 1
    case added
    case renamed
    case modified
    case deleted
    case conflicted

    static func < (a: GitFileStatus, b: GitFileStatus) -> Bool { a.rawValue < b.rawValue }

    /// 행 끝에 붙이는 한 글자(VS Code 관례).
    var letter: String {
        switch self {
        case .untracked:  return "U"
        case .added:      return "A"
        case .renamed:    return "R"
        case .modified:   return "M"
        case .deleted:    return "D"
        case .conflicted: return "!"
        }
    }

    /// porcelain v1의 두 글자(XY)를 상태 하나로 줄인다.
    init?(porcelain xy: Substring) {
        let chars = Array(xy)
        guard chars.count == 2 else { return nil }
        let (x, y) = (chars[0], chars[1])
        if x == "?" && y == "?" { self = .untracked; return }
        if x == "!" { return nil }   // 무시된 파일
        if x == "U" || y == "U" || (x == "A" && y == "A") || (x == "D" && y == "D") {
            self = .conflicted; return
        }
        if x == "D" || y == "D" { self = .deleted; return }
        if x == "M" || y == "M" || x == "T" || y == "T" { self = .modified; return }
        if x == "R" || x == "C" { self = .renamed; return }
        if x == "A" { self = .added; return }
        return nil
    }
}

/// 폴더 하나(트리 루트)에 대한 git 상태 스냅샷.
///
/// 키는 `TreePane.changeKey`로 정규화한 절대 경로다(/private/tmp와 /tmp가 섞이지 않게).
struct GitStatusSnapshot {
    /// 상태가 있는 파일.
    var files: [String: GitFileStatus] = [:]
    /// 안쪽에 상태가 있는 폴더 → 그중 가장 강한 상태.
    var folders: [String: GitFileStatus] = [:]
    /// 통째로 추적되지 않는 폴더(`-unormal`은 안쪽 파일을 낱낱이 나열하지 않는다).
    var untrackedFolders: [String] = []

    func status(forPath path: String, isDirectory: Bool) -> GitFileStatus? {
        if let hit = isDirectory ? folders[path] : files[path] { return hit }
        // 추적되지 않는 폴더 안의 항목은 모두 추적되지 않는다.
        if untrackedFolders.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return .untracked
        }
        return nil
    }

    var isEmpty: Bool { files.isEmpty && folders.isEmpty && untrackedFolders.isEmpty }
}

/// `git status`를 백그라운드에서 돌려 스냅샷을 만든다.
enum GitStatusReader {
    /// 쓸 git 실행 파일. 없으면 nil(git 상태 표시를 끈다).
    ///
    /// /usr/bin/git은 명령줄 도구가 없는 맥에서 실행하면 설치 안내 창을 띄운다.
    /// 그래서 Homebrew git을 먼저 찾고, /usr/bin/git은 명령줄 도구나 Xcode가 있을 때만 쓴다.
    static let gitURL: URL? = {
        let fm = FileManager.default
        for path in ["/opt/homebrew/bin/git", "/usr/local/bin/git"] where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let developerDirs = ["/Library/Developer/CommandLineTools/usr/bin/git",
                             "/Applications/Xcode.app/Contents/Developer/usr/bin/git"]
        if developerDirs.contains(where: fm.isExecutableFile(atPath:)) {
            return URL(fileURLWithPath: "/usr/bin/git")
        }
        return nil
    }()

    /// root가 git 저장소 안에 있으면 root 아래 항목의 상태를 읽는다. 저장소가 아니면 nil.
    static func read(root: URL) -> GitStatusSnapshot? {
        guard let git = gitURL else { return nil }
        guard let top = run(git, ["rev-parse", "--show-toplevel"], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !top.isEmpty else { return nil }
        // pathspec "."로 root 아래만 본다. 큰 저장소의 한 하위 폴더만 열었을 때 전체를 훑지 않게.
        // porcelain v1의 경로는 늘 저장소 최상위 기준이다.
        guard let output = run(git, ["status", "--porcelain=v1", "-z", "--untracked-files=normal", "--", "."],
                               in: root) else { return nil }

        let topKey = TreePane.changeKey(top)
        let rootKey = TreePane.changeKey(root.path)
        var snapshot = GitStatusSnapshot()
        let entries = output.split(separator: "\0", omittingEmptySubsequences: true)
        var index = 0
        while index < entries.count {
            let entry = entries[index]
            index += 1
            guard entry.count > 3, let status = GitFileStatus(porcelain: entry.prefix(2)) else { continue }
            // 이름 바꾸기·복사는 새 경로 뒤에 옛 경로가 한 칸 더 온다.
            let x = entry.prefix(1)
            if x == "R" || x == "C" { index += 1 }

            var relative = String(entry.dropFirst(3))
            let isFolder = relative.hasSuffix("/")
            if isFolder { relative.removeLast() }
            let path = topKey + "/" + relative
            guard path.hasPrefix(rootKey + "/") else { continue }

            if isFolder {
                snapshot.untrackedFolders.append(path)
            } else {
                snapshot.files[path] = max(snapshot.files[path] ?? status, status)
            }
            // 상위 폴더를 root 직전까지 가장 강한 상태로 칠한다.
            var parent = (path as NSString).deletingLastPathComponent
            if isFolder { parent = path }
            while parent.count > rootKey.count {
                snapshot.folders[parent] = max(snapshot.folders[parent] ?? status, status)
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return snapshot
    }

    /// 파일의 마지막 커밋본(HEAD). 저장소 밖이거나, 아직 커밋된 적 없는 파일이면 nil.
    ///
    /// `HEAD:./이름`은 실행 폴더 기준 경로라 파일이 든 폴더에서 돌린다. 저장소 최상위 기준
    /// 상대 경로를 따로 구하지 않아도 되고, /private/tmp 같은 경로 정규화 문제도 피한다.
    static func committedContent(of file: URL) -> String? {
        guard let git = gitURL else { return nil }
        return run(git, ["show", "HEAD:./" + file.lastPathComponent],
                   in: file.deletingLastPathComponent())
    }

    /// git을 실행해 표준 출력을 돌려준다. 실패하면 nil.
    private static func run(_ git: URL, _ arguments: [String], in directory: URL) -> String? {
        let process = Process()
        process.executableURL = git
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // 잠금 파일을 만들지 않게 한다(사용자가 터미널에서 돌리는 git과 부딪히지 않도록).
        var env = ProcessInfo.processInfo.environment
        env["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
