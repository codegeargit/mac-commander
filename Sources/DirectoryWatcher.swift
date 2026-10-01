import Foundation

/// 루트 폴더 하위 트리 전체의 파일시스템 변경을 FSEvents로 감시한다.
///
/// Finder 등 외부에서 파일을 옮기거나 만들거나 지우면 콜백을 호출해
/// 앱이 트리를 다시 스캔하도록 한다. 앱 자신이 만든 변경도 함께 감지되지만,
/// 재스캔은 idempotent하므로 무해하다(짧은 debounce로 폭주만 막는다).
///
/// 콜백은 메인 큐에서 호출된다(WorkspaceStore는 @MainActor). 이번에 바뀐 경로들을 함께 넘긴다
/// (FSEvents가 돌려준 실제 경로라 /tmp → /private/tmp처럼 심볼릭 링크가 풀려 있을 수 있다).
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: ([String]) -> Void

    /// 연속된 변경 이벤트를 묶기 위한 debounce 간격(초).
    private let latency: CFTimeInterval = 0.3

    /// - Parameters:
    ///   - url: 감시할 루트 폴더.
    ///   - onChange: 변경 감지 시 메인 큐에서 호출되는 클로저. 인자는 바뀐 경로들.
    init?(url: URL, onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
        guard start(at: url) else { return nil }
    }

    deinit { stop() }

    private func start(at url: URL) -> Bool {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            // UseCFTypes 플래그를 줬으므로 eventPaths는 CFArray<CFString>이다.
            let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
            // FSEvents는 자체 큐에서 호출한다. 콜백을 메인 큐로 넘긴다.
            DispatchQueue.main.async { watcher.onChange(paths) }
        }

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot |
            kFSEventStreamCreateFlagUseCFTypes
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return false }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return false
        }
        return true
    }

    private func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
