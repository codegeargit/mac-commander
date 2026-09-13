import SwiftUI

/// Finder의 "폴더로 이동"(⌘⇧G)에 해당하는 시트.
/// 폴더 경로를 텍스트로 입력받아 존재하면 그 폴더로 워크스페이스를 이동한다.
/// `~` 확장을 지원하고, 경로가 없으면 오류 메시지를 표시한다.
struct GoToFolderView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    /// 입력한 경로. 시트가 열릴 때 현재 루트 경로로 초기화한다.
    @State private var path: String
    /// 존재하지 않는 경로일 때 오류 문구를 표시할지.
    @State private var showError = false
    /// 입력 필드로 포커스를 옮기기 위한 키.
    @FocusState private var fieldFocused: Bool

    init(initialPath: String) {
        _path = State(initialValue: initialPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc.string(.goToFolderPrompt))
                .font(.system(size: 12))
                .foregroundStyle(Palette.textPrimary)

            TextField(loc.string(.goToFolderPlaceholder), text: $path)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .focused($fieldFocused)
                .onSubmit(go)
                .onChange(of: path) { _, _ in showError = false }

            if showError {
                Text(loc.string(.goToFolderInvalid))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(loc.string(.goCancel)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(loc.string(.goConfirm), action: go)
                    .keyboardShortcut(.defaultAction)
                    .disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(Palette.panelBackground)
        .onAppear { fieldFocused = true }
    }

    /// 입력한 경로로 이동을 시도. 실패하면 오류를 표시하고 시트를 유지한다.
    private func go() {
        if store.goToPath(path) {
            dismiss()
        } else {
            showError = true
        }
    }
}
