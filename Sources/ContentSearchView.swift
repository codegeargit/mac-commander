import SwiftUI

/// 폴더 전체 본문 검색 창(⇧⌘F).
///
/// 결과를 고르면 그 문서를 열고 **같은 검색어로 문서 내 찾기(⌘F)를 이어서 실행**한다.
/// 줄 번호로 곧장 뛰는 대신 이렇게 잇는 이유는, 마크다운은 렌더된 화면과 원문 줄 번호가
/// 일대일로 맞지 않기 때문이다.
struct ContentSearchView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var loc: LocalizationManager
    @ObservedObject var index: FileIndex
    @ObservedObject var search: ContentSearch
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if search.matches.isEmpty {
                emptyState
            } else {
                resultList
            }
            Divider()
            footer
        }
        .frame(width: 680, height: 460)
        .background(Palette.viewerBackground)
        .onAppear {
            index.refreshIfNeeded(root: store.root?.url, showAllFiles: store.showAllFiles)
            fieldFocused = true
        }
        .onDisappear { search.cancel() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .foregroundStyle(Palette.accent)
            TextField(loc.string(.contentSearchPlaceholder), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Palette.textPrimary)
                .focused($fieldFocused)
                .onSubmit { runSearch() }
                .onExitCommand { dismiss() }
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    moveSelection(press.key == .downArrow ? 1 : -1)
                    return .handled
                }
            if index.isScanning || search.isSearching {
                ProgressView().controlSize(.small)
            }
            Button(loc.string(.contentSearchRun)) { runSearch() }
                .keyboardShortcut(.defaultAction)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Palette.headerBackground)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: statusIcon)
                .font(.system(size: 28))
                .foregroundStyle(Palette.textMuted)
            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusIcon: String {
        if search.isSearching { return "hourglass" }
        return search.completedQuery.isEmpty ? "text.magnifyingglass" : "questionmark.folder"
    }

    private var statusText: String {
        if search.isSearching { return loc.string(.contentSearchRunning) }
        if search.completedQuery.isEmpty { return loc.string(.contentSearchHint) }
        return loc.string(.contentSearchNoMatch(search.completedQuery))
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(search.matches.enumerated()), id: \.element.id) { position, match in
                        row(match: match, isSelected: position == selection)
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

    private func row(match: ContentMatch, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Palette.selectForeground : Palette.accentDim)
                Text(match.url.lastPathComponent)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? Palette.selectForeground : Palette.textPrimary)
                Text(loc.string(.contentSearchLine(match.lineNumber)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isSelected ? Palette.selectForeground.opacity(0.8) : Palette.textMuted)
                Text(relativeParent(of: match.url))
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Palette.selectForeground.opacity(0.8) : Palette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
            }
            Text(match.line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isSelected ? Palette.selectForeground : Palette.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Palette.selectBackground : .clear)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if search.truncated {
                Label(loc.string(.contentSearchTruncated(ContentSearch.maxMatches)),
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textWarning)
            } else if !search.matches.isEmpty {
                Text(loc.string(.contentSearchCount(search.matches.count)))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
            }
            Spacer()
            Text(loc.string(.contentSearchKeysHint))
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(Palette.headerBackground)
    }

    private func relativeParent(of url: URL) -> String {
        let rootPath = store.root?.url.path ?? ""
        let parent = url.deletingLastPathComponent().path
        guard parent.hasPrefix(rootPath) else { return parent }
        let relative = String(parent.dropFirst(rootPath.count))
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
    }

    private func moveSelection(_ delta: Int) {
        guard !search.matches.isEmpty else { return }
        selection = min(max(selection + delta, 0), search.matches.count - 1)
    }

    private func runSearch() {
        selection = 0
        search.run(query: query, in: index.entries)
    }

    private func openSelected() {
        guard search.matches.indices.contains(selection) else { return }
        store.openFromContentSearch(search.matches[selection].url, query: search.completedQuery)
        dismiss()
    }
}
