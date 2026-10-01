import AppKit

/// 앱 밖에서 들어온 "이 경로를 열어 줘" 요청을 받는다.
///
/// Finder의 다음으로 열기, 독 아이콘에 끌어 놓기, 터미널의 `mcom` 명령(`open -b`)이 모두
/// `application(_:open:)`으로 들어온다. 앱이 막 켜지는 중이면 세션 복원보다 먼저 올 수 있어
/// 복원이 끝날 때까지 쌓아 두었다가 넘긴다(아니면 복원이 방금 연 폴더를 덮어쓴다).
@MainActor
final class ExternalOpenRouter {
    static let shared = ExternalOpenRouter()

    private var pending: [URL] = []
    private var handler: ((URL) -> Void)?

    /// 스토어가 준비되면 연결한다. 그사이 쌓인 요청을 바로 처리한다.
    func connect(_ handler: @escaping (URL) -> Void) {
        self.handler = handler
        let queued = pending
        pending = []
        // 여러 개가 함께 오면 마지막 것만 연다. 트리 루트는 하나라 앞의 것은 바로 덮인다.
        if let last = queued.last { handler(last) }
    }

    func open(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard let last = fileURLs.last else { return }
        NSApp.activate(ignoringOtherApps: true)
        if let handler {
            handler(last)
        } else {
            pending.append(last)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 이 메서드가 있으면 SwiftUI가 열기 요청마다 새 창을 만들지 않고 여기로 넘긴다.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { ExternalOpenRouter.shared.open(urls) }
    }
}

/// `mcom` 명령줄 도구를 /usr/local/bin에 링크로 설치한다(VS Code의 `code` 설치와 같은 방식).
///
/// 링크라서 앱이 업데이트돼도 다시 설치할 필요가 없다. /usr/local/bin에 쓸 권한이 없으면
/// (Apple Silicon 맥은 보통 폴더 자체가 없다) 관리자 암호를 물어 만든다.
@MainActor
enum CommandLineToolInstaller {
    static let linkPath = "/usr/local/bin/mcom"

    static var scriptPath: String? { Bundle.main.path(forResource: "mcom", ofType: nil) }

    /// 이미 이 앱의 스크립트를 가리키는 링크가 있는지.
    static var isInstalled: Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath) else {
            return false
        }
        return target == scriptPath
    }

    static func install() {
        let loc = LocalizationManager.shared
        guard let script = scriptPath else {
            show(loc.string(.cliInstallFailed("mcom script missing from app bundle")), style: .warning)
            return
        }
        if let error = installDirectly(script: script) {
            NSLog("[CLI] direct install failed: \(error)")
            // 같은 이름의 다른 프로그램이 있으면 덮어쓰지 않는다(관리자 경로의 ln -sf는 덮어쓴다).
            if FileManager.default.fileExists(atPath: linkPath),
               (try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)) == nil {
                show(loc.string(.cliInstallFailed(error)), style: .warning)
                return
            }
            // 권한이 없으면 관리자 암호를 물어 다시 시도한다.
            if let adminError = installAsAdmin(script: script) {
                // 사용자가 암호 창을 취소한 경우(-128)는 조용히 끝낸다.
                if adminError != "-128" {
                    show(loc.string(.cliInstallFailed(adminError)), style: .warning)
                }
                return
            }
        }
        show(loc.string(.cliInstalled(linkPath)), style: .informational)
    }

    /// 권한 없이 링크를 만든다. 성공하면 nil, 실패하면 오류 문구.
    private static func installDirectly(script: String) -> String? {
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: "/usr/local/bin", withIntermediateDirectories: true)
            // 옛 링크(다른 위치의 앱을 가리키는 것)는 지우고 새로 건다. 일반 파일은 건드리지 않는다.
            if (try? fm.destinationOfSymbolicLink(atPath: linkPath)) != nil {
                try fm.removeItem(atPath: linkPath)
            } else if fm.fileExists(atPath: linkPath) {
                return "\(linkPath) already exists"
            }
            try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: script)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 관리자 권한으로 링크를 만든다. 성공하면 nil, 실패하면 오류 번호나 문구.
    private static func installAsAdmin(script: String) -> String? {
        func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = "mkdir -p /usr/local/bin && ln -sf \(quoted(script)) \(quoted(linkPath))"
        let source = "do shell script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return nil }
        if let number = errorInfo[NSAppleScript.errorNumber] as? Int, number == -128 { return "-128" }
        return (errorInfo[NSAppleScript.errorMessage] as? String) ?? "unknown error"
    }

    private static func show(_ message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = LocalizationManager.shared.string(.cliInstallTitle)
        alert.informativeText = message
        alert.runModal()
    }
}
