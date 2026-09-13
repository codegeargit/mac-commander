import SwiftUI

/// 파일명으로 문서를 찾아 바로 여는 창(⌘P).
///
/// 트리를 짚어 내려가지 않고 이름 일부만으로 문서를 연다. 공백으로 나눈 토큰이
/// 모두 들어 있는 파일만 남기므로 `design token`처럼 두 단어를 섞어 좁힐 수 있다.
/// 대상은 트리 표시 필터(MD/ALL)와 같은 범위다.
struct QuickOpenView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager
    @ObservedObject var index: FileIndex
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    /// 목록에서 지금 고른 항목의 위치.
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    /// 현재 검색어에 대한 결과. 인덱스가 갱신되면(revision) 다시 계산된다.
    private var results: [URL] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        _ = index.revision
        return index.matches(query)
    }

    private var rootPath: String { store.root?.url.path ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if results.isEmpty {
                emptyState
            } else {
                resultList
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 420)
        .background(Palette.viewerBackground)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.accent)
            TextField(loc.string(.quickOpenPlaceholder), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Palette.textPrimary)
                .focused($fieldFocused)
                .onSubmit { openSelected() }
                .onExitCommand { dismiss() }
                // 목록 이동은 입력창에 커서를 둔 채로 해야 한다.
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    moveSelection(press.key == .downArrow ? 1 : -1)
                    return .handled
                }
                // 검색어가 바뀌면 첫 결과부터 다시 고른다.
                .onChange(of: query) { _, _ in selection = 0 }
            if index.isScanning {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Palette.headerBackground)
        .onAppear {
            index.refreshIfNeeded(root: store.root?.url, showAllFiles: store.showAllFiles)
            fieldFocused = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: query.isEmpty ? "doc.text.magnifyingglass" : "questionmark.folder")
                .font(.system(size: 28))
                .foregroundStyle(Palette.textMuted)
            Text(loc.string(query.isEmpty ? .quickOpenHint : .quickOpenNoMatch))
                .font(.system(size: 12))
                .foregroundStyle(Palette.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element) { position, url in
                        row(url: url, isSelected: position == selection)
                            .id(position)
                            .onTapGesture {
                                selection = position
                                openSelected()
                            }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selection) { _, new in
                withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private func row(url: URL, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName(for: url))
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Palette.selectForeground : Palette.accentDim)
                .frame(width: 14)
            Text(url.lastPathComponent)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(isSelected ? Palette.selectForeground : Palette.textPrimary)
                .lineLimit(1)
            Text(parentPath(of: url))
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Palette.selectForeground.opacity(0.8) : Palette.textMuted)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(isSelected ? Palette.selectBackground : .clear)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if index.truncated {
                // 상한에 걸렸으면 결과가 전부가 아님을 밝힌다. 조용히 자르면 "없다"로 읽힌다.
                Label(loc.string(.quickOpenTruncated(FileIndex.maxEntries)),
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textWarning)
            } else if !results.isEmpty {
                Text(loc.string(.quickOpenCount(results.count)))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
            }
            Spacer()
            Text(loc.string(.quickOpenKeysHint))
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(Palette.headerBackground)
    }

    /// 루트 기준 상위 폴더 경로(루트 바로 아래면 비어 있다).
    private func parentPath(of url: URL) -> String {
        let parent = url.deletingLastPathComponent().path
        guard parent.hasPrefix(rootPath) else { return parent }
        let relative = String(parent.dropFirst(rootPath.count))
        return relative.isEmpty ? "" : relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
    }

    private func iconName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if FileNode.pdfExtensions.contains(ext) { return "doc.richtext" }
        if FileNode.imageExtensions.contains(ext) { return "photo" }
        if FileNode.richDocExtensions.contains(ext) { return "doc.plaintext" }
        if FileNode.markdownExtensions.contains(ext) { return "doc.text" }
        return "doc"
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
    }

    private func openSelected() {
        guard results.indices.contains(selection) else { return }
        store.openMarkdown(at: results[selection], inPanel: store.activePanelIndex)
        dismiss()
    }
}
