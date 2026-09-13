import SwiftUI
import AppKit

/// 창 하단 상태바. 트리 커서 항목의 정보(이름·크기·수정일)와
/// 다중 선택/현재 폴더 항목 수를 표시한다. Total Commander의 하단 상태줄에 대응.
struct StatusBarView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var license: LicenseManager

    /// 현재 표시 중인 주 로컬 IPv4 주소(없으면 nil).
    @State private var localIP: String?
    /// 방금 복사됨을 잠깐 알리는 플래그.
    @State private var justCopied = false

    var body: some View {
        HStack(spacing: 12) {
            // 좌측: 커서 항목 정보(또는 선택 요약)
            Text(leadingText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            // 우측: 로컬 IP (클릭하면 복사)
            ipView

            // 우측: 현재 폴더 항목 수
            if store.root != nil {
                Text(loc.string(.statusItemsCount(store.currentFolderItemCount)))
                    .lineLimit(1)
                    .fixedSize()
            }

            // 맨 오른쪽: 후원자 배지. 유효한 후원자 키가 있을 때만.
            if license.isSupporter {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.pink)
                    .help(loc.string(.licenseStatusActive))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.textMuted)
        .padding(.horizontal, 10)
        .frame(height: 22)
        .frame(maxWidth: .infinity)
        .background(Palette.headerBackgroundInactive)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.divider).frame(height: 1)
        }
        .onAppear { refreshIP() }
    }

    /// 로컬 IP 표시 뷰. IP가 있으면 클릭 가능한 버튼으로, 없으면 옅게 표시.
    @ViewBuilder
    private var ipView: some View {
        if let ip = localIP {
            Button {
                copyIP(ip)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: justCopied ? "checkmark" : "network")
                        .font(.system(size: 10))
                    Text(justCopied ? loc.string(.statusIPCopied(ip)) : loc.string(.statusIP(ip)))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(justCopied ? Palette.accent : Palette.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(loc.string(.statusIPCopyHint))
        } else {
            Text(loc.string(.statusIPUnavailable))
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// IP를 다시 조회한다(네트워크 변경 대응).
    private func refreshIP() {
        localIP = LocalIPProvider.primaryIPv4
    }

    /// IP를 클립보드에 복사하고 잠깐 피드백을 보여준다.
    private func copyIP(_ ip: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(ip, forType: .string)
        withAnimation { justCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { justCopied = false }
        }
    }

    /// 좌측 텍스트: 선택이 있으면 선택 요약, 없으면 커서 항목 정보.
    private var leadingText: String {
        if store.markedCount > 0 {
            let size = Self.formatSize(store.markedTotalSize)
            return loc.string(.statusSelected(store.markedCount, size))
        }
        guard let node = store.cursorNode else { return loc.string(.statusEmpty) }
        if node.isDirectory {
            return "\(node.name)  ·  \(loc.string(.statusFolder))"
        }
        let size = Self.formatSize(WorkspaceStore.fileSize(of: node.url))
        var parts = [node.name, size]
        if let modified = Self.formatModified(node.url) {
            parts.append(modified)
        }
        return parts.joined(separator: "  ·  ")
    }

    /// 바이트 크기를 사람이 읽기 쉬운 문자열로(예: "12.3 MB").
    static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 파일 수정일을 짧은 형식으로. 실패 시 nil.
    static func formatModified(_ url: URL) -> String? {
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
