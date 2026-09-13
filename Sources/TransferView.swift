import SwiftUI

/// 반대편 트리로 복사·이동하기 전 확인 창(듀얼 모드 F5·F6).
///
/// Total Commander의 복사 창처럼 대상 폴더 경로를 보여 주고 고칠 수 있게 한다.
/// Enter로 실행, Esc로 취소.
///
/// 보내는 방향은 고른 순서와 항목 종류로 자동으로 정한다(`transferSourcePaneIndex`).
/// 뜻과 다를 수 있으니 방향을 글로 보여 주고 한 번에 뒤집는 버튼을 둔다.
struct TransferView: View {
    let request: TransferRequest

    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager

    /// 대상 폴더 경로(반대편 트리 기준으로 채워 둔다).
    @State private var path: String
    @FocusState private var fieldFocused: Bool

    /// 목록에 이름을 보여 줄 최대 개수. 더 많으면 "외 N개"로 줄인다.
    private static let previewLimit = 5

    init(request: TransferRequest) {
        self.request = request
        _path = State(initialValue: request.destinationPath)
    }

    /// 방향을 바꾸면 스토어의 요청이 바뀐다. 창에는 늘 최신 요청을 보여 준다.
    private var current: TransferRequest { store.pendingTransfer ?? request }

    private var title: String {
        loc.string(current.isMove ? .transferMoveTitle : .transferCopyTitle)
    }

    /// 지금 경로로 실행하면 안 되는 이유(없으면 nil).
    private var problem: String? {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return store.transferProblem(current, destinationPath: path)
    }

    private var canConfirm: Bool {
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && problem == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: current.isMove ? "arrow.right.doc.on.clipboard" : "doc.on.doc")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textHeading)

            // 보내는 방향 + 뒤집기
            HStack(spacing: 8) {
                Text(loc.string(.transferDirection(current.sourcePaneIndex == 0)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accent)
                Spacer()
                Button(action: { store.reverseTransfer() }) {
                    Label(loc.string(.transferReverse), systemImage: "arrow.left.arrow.right")
                }
                .disabled(!store.canReverseTransfer)
            }

            Text(loc.string(current.isMove
                            ? .transferMovePrompt(current.sources.count)
                            : .transferCopyPrompt(current.sources.count)))
                .font(.system(size: 12))
                .foregroundStyle(Palette.textPrimary)

            // 보낼 항목 이름(앞 몇 개). 폴더인지 파일인지 아이콘으로 구분한다.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(current.sources.prefix(Self.previewLimit), id: \.self) { url in
                    Label {
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: url.hasDirectoryPath || isDirectory(url) ? "folder.fill" : "doc")
                            .foregroundStyle(Palette.textFolder)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                }
                if current.sources.count > Self.previewLimit {
                    Text("… +\(current.sources.count - Self.previewLimit)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.textMuted)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(loc.string(.transferTo))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
                TextField("", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .focused($fieldFocused)
                    .onSubmit { if canConfirm { confirm() } }
            }

            // 실행할 수 없는 이유를 바로 보여 준다(조용히 무시되지 않게).
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(loc.string(.cancel)) { store.cancelTransfer() }
                    .keyboardShortcut(.cancelAction)
                Button(title, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Palette.panelBackground)
        .onAppear { fieldFocused = true }
        // 방향을 바꾸면 대상 폴더도 새로 채운다.
        .onChange(of: current.destinationPath) { _, newPath in path = newPath }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func confirm() {
        store.confirmTransfer(destinationPath: path)
    }
}
