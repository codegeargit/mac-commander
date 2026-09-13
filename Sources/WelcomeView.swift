import SwiftUI

/// 열어둔 폴더가 없을 때 창 전체에 나오는 시작 화면.
///
/// 세 가지 일을 한다.
/// - 첫 실행에 이 앱이 무엇을 하는지, 무엇을 해야 하는지 알려준다.
/// - 지난 세션의 폴더를 되살리지 못했으면 **왜** 못 열었는지 밝힌다.
///   (예전에는 조용히 빈 화면으로 떨어져 앱이 하던 일을 잊은 것처럼 보였다)
/// - 최근에 열었던 폴더를 한 번에 다시 열게 한다.
struct WelcomeView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(Palette.accent)

                Text(loc.string(.welcomeTitle))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.textHeading)

                Text(loc.string(.welcomeBody))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                if let failure = store.restoreFailure {
                    restoreFailureNotice(failure)
                }

                Button(action: { store.promptOpenFolder() }) {
                    Text(loc.string(.welcomeOpenFolder))
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("o", modifiers: .command)

                Text(loc.string(.welcomeDragHint))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
            }

            if !store.recentFolders.isEmpty {
                recentSection
                    .padding(.top, 26)
            }

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.viewerBackground)
    }

    /// 지난 폴더를 못 연 이유 안내. 사용자가 치울 수 있게 닫기를 둔다.
    private func restoreFailureNotice(_ failure: WorkspaceStore.RestoreFailure) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textWarning)
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.string(.welcomeRestoreFailed))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                if let path = failure.path {
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(2)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                }
                Text(loc.string(.welcomeRestoreFailedHint))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
            }
            Button(action: { store.dismissRestoreFailure() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
            }
            .buttonStyle(.plain)
            .help(loc.string(.findClose))
        }
        .padding(10)
        .frame(maxWidth: 460, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.textWarning.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.textWarning.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(loc.string(.welcomeRecent))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.accent)
                Spacer()
                Button(loc.string(.welcomeClearRecent)) { store.clearRecentFolders() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
            }

            VStack(spacing: 0) {
                ForEach(store.recentFolders) { recent in
                    recentRow(recent)
                }
            }
            .background(Palette.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Palette.divider, lineWidth: 1)
            )
        }
        .frame(width: 460)
    }

    private func recentRow(_ recent: RecentFolder) -> some View {
        Button(action: { store.openRecentFolder(recent) }) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textFolder)
                Text(recent.name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                Text(recent.path)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(loc.string(.welcomeRemoveRecent)) { store.removeRecentFolder(recent) }
        }
    }
}
