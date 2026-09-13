import Foundation
import CryptoKit

/// Word·Office 문서를 PDF로 변환해 캐시한다.
///
/// QuickLook의 .docx 렌더러는 표의 고정 폭(`w:tblW type="dxa"`)을 무시하고 열을 내용에
/// 맞춰 좁힌다. 그래서 페이지를 가득 채워야 할 표가 왼쪽으로 뭉치고 글꼴도 대체된다.
/// LibreOffice로 변환한 PDF는 Word가 직접 내보낸 PDF와 열 위치·글꼴이 거의 일치해,
/// 변환이 가능하면 그 PDF를 대신 보여준다.
///
/// LibreOffice가 없으면 nil을 돌려주고, 호출 측은 QuickLook 표시를 그대로 유지한다.
/// 즉 이 경로는 "있으면 더 정확해지는" 보강이지 필수 의존이 아니다.
actor DocumentConverter {
    static let shared = DocumentConverter()

    /// 변환 대상. 나머지 형식(iWork 등)은 LibreOffice가 제대로 다루지 못하거나
    /// QuickLook 쪽이 더 나아서 변환하지 않는다.
    static let convertibleExtensions: Set<String> = [
        "docx", "doc", "rtf", "xlsx", "xls", "pptx", "ppt",
    ]

    /// 변환이 너무 오래 걸리면(손상된 문서 등) 포기한다.
    private static let timeout: TimeInterval = 120

    /// 같은 문서에 대한 중복 변환을 막는다(캐시 키 → 진행 중인 작업).
    private var running: [String: Task<URL?, Never>] = [:]

    // MARK: - 경로

    /// 변환 결과를 두는 캐시 폴더.
    private static var cacheDirectory: URL? {
        let id = Bundle.main.bundleIdentifier ?? "ai.codegear.MacCommander"
        guard let base = FileManager.default.urls(for: .cachesDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("ConvertedDocuments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// LibreOffice 실행 파일. 앱 번들과 Homebrew 설치 위치를 훑는다.
    private static var sofficePath: String? {
        let candidates = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/opt/homebrew/bin/soffice",
            "/usr/local/bin/soffice",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// LibreOffice를 쓸 수 있는 환경인지.
    nonisolated static var isAvailable: Bool { sofficePath != nil }

    /// 이 파일을 변환해서 보여줄 수 있는지(형식 + 도구 설치 여부).
    nonisolated static func canConvert(_ url: URL) -> Bool {
        isAvailable && convertibleExtensions.contains(url.pathExtension.lowercased())
    }

    /// 원본 경로·수정시각·크기로 만든 캐시 키. 문서가 바뀌면 키도 바뀌어 자동으로 다시 변환된다.
    private static func cacheKey(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        else { return nil }
        let stamp = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values.fileSize ?? 0
        // hashValue는 실행할 때마다 달라져(시드 랜덤화) 캐시 키로 못 쓴다. SHA256으로 고정한다.
        let digest = SHA256.hash(data: Data("\(url.path)|\(stamp)|\(size)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 이미 변환해 둔 PDF가 있으면 그 경로(디스크 캐시 조회, 즉시 반환).
    nonisolated static func cachedPDF(for url: URL) -> URL? {
        guard let dir = cacheDirectory, let key = cacheKey(for: url) else { return nil }
        let path = dir.appendingPathComponent("\(key).pdf")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    // MARK: - 변환

    /// 문서를 PDF로 변환해 캐시 경로를 돌려준다. 캐시가 있으면 바로 반환.
    /// 변환할 수 없는 형식이거나 LibreOffice가 없으면 nil.
    func pdf(for url: URL) async -> URL? {
        guard Self.canConvert(url) else { return nil }
        if let hit = Self.cachedPDF(for: url) { return hit }
        guard let dir = Self.cacheDirectory, let key = Self.cacheKey(for: url) else { return nil }

        // 같은 문서를 이미 변환 중이면 그 결과를 함께 기다린다.
        if let inFlight = running[key] { return await inFlight.value }

        let destination = dir.appendingPathComponent("\(key).pdf")
        let task = Task<URL?, Never> {
            await Self.run(source: url, destination: destination, profileParent: dir)
        }
        running[key] = task
        let result = await task.value
        running[key] = nil
        return result
    }

    /// soffice를 헤드리스로 돌려 PDF를 만든다. 성공하면 목적지 URL.
    private static func run(source: URL, destination: URL, profileParent: URL) async -> URL? {
        guard let soffice = sofficePath else { return nil }

        // 출력 파일명은 soffice가 "원본이름.pdf"로 정한다. 이름 충돌과 찌꺼기를 피하려고
        // 임시 폴더에 뽑은 뒤 캐시 경로로 옮긴다.
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-convert-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)) != nil
        else { return nil }
        defer { try? FileManager.default.removeItem(at: work) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: soffice)
        process.arguments = [
            // 사용자가 LibreOffice를 열어 둔 상태면 기본 프로필이 잠겨 변환이 실패한다.
            // 전용 프로필을 따로 줘서 GUI와 충돌하지 않게 한다.
            "-env:UserInstallation=file://\(profileParent.appendingPathComponent("LibreOfficeProfile").path)",
            "--headless", "--norestore", "--invisible",
            "--convert-to", "pdf",
            "--outdir", work.path,
            source.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let finished: Bool = await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                process.terminationHandler = { _ in cont.resume(returning: true) }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    cont.resume(returning: false)
                }
                // 멈춘 변환이 영원히 남지 않게 시간 제한을 건다.
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning { process.terminate() }
                }
            }
        } onCancel: {
            // 사용자가 다른 파일로 옮겨 가면 변환도 멈춘다.
            if process.isRunning { process.terminate() }
        }

        guard finished, !Task.isCancelled else { return nil }

        // soffice는 실패해도 0으로 끝나는 경우가 있어 결과 파일 존재로 판정한다.
        let produced = work.appendingPathComponent(
            source.deletingPathExtension().lastPathComponent).appendingPathExtension("pdf")
        guard FileManager.default.fileExists(atPath: produced.path) else { return nil }

        try? FileManager.default.removeItem(at: destination)
        guard (try? FileManager.default.moveItem(at: produced, to: destination)) != nil else { return nil }
        return destination
    }
}
