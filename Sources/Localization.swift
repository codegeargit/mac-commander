import SwiftUI

/// 지원 언어.
enum AppLanguage: String, CaseIterable, Identifiable {
    case korean = "ko"
    case english = "en"

    var id: String { rawValue }

    /// 환경설정 등에 표시할 이름(각 언어 자기 이름으로).
    var displayName: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        }
    }
}

/// 앱 전역 언어 상태. 변경 시 @Published로 모든 뷰가 즉시 갱신된다.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "app.language") }
    }

    private init() {
        // 저장값 없으면 시스템 언어가 한국어면 ko, 아니면 en.
        if let saved = UserDefaults.standard.string(forKey: "app.language"),
           let lang = AppLanguage(rawValue: saved) {
            language = lang
        } else {
            let sys = Locale.preferredLanguages.first ?? "en"
            language = sys.hasPrefix("ko") ? .korean : .english
        }
    }

    /// 키에 해당하는 현재 언어 문자열.
    func string(_ key: L10n) -> String {
        key.value(for: language)
    }
}

/// 지역화 문자열 키. 각 케이스가 (한국어, 영어) 쌍을 가진다.
enum L10n {
    // 트리 / 파일 관리
    case newMarkdownFile
    case newFolder
    case rename
    case delete
    case openInTerminal      // 트리 컨텍스트 메뉴: 터미널에서 열기
    case copyPath            // 절대 경로 복사
    case copyRelativePath    // 워크스페이스 루트 기준 상대 경로 복사
    case enterFolder         // 폴더 진입(새 루트로)
    case goToParent          // 메뉴용(단축키 없음)
    case goToParentTooltip   // 헤더 버튼 툴팁(단축키 포함)
    case goToFolder          // 메뉴: 폴더로 이동 (⌘⇧G)
    case goToFolderTitle     // 시트 제목
    case goToFolderPrompt    // 경로 입력 안내
    case goToFolderPlaceholder // 입력 필드 placeholder
    case goToFolderInvalid   // 존재하지 않는 경로 오류
    case goCancel
    case goConfirm

    // 뷰어
    case selectFilePrompt    // 빈 뷰어 안내
    case fontSmaller
    case fontReset
    case fontLarger
    case addPanel
    case closePanel
    case editDocument       // 보기→편집 토글 버튼/툴팁
    case previewDocument    // 편집→보기 토글 버튼/툴팁
    case saveDocument       // 저장 버튼/툴팁
    case unsavedBadge       // 저장 안 됨 표시 툴팁
    case toggleTerminal     // 터미널 패널 열기/닫기 토글
    case launchClaudeCode   // 터미널에서 Claude Code 실행
    case terminalTitle      // 터미널 패널 헤더 제목
    case terminalMoveBottom // 터미널을 아래로 옮기기
    case terminalMoveRight  // 터미널을 오른쪽으로 옮기기
    case zoomIn             // PDF 확대
    case zoomOut            // PDF 축소
    case zoomReset          // PDF 폭 맞춤으로 복귀(라벨 클릭)
    case zoomFit            // PDF 폭 맞춤 상태 라벨

    // 문서 내 찾기(⌘F)
    case findPlaceholder    // 찾기 입력 placeholder
    case findPrevious       // 위로 찾기 버튼
    case findNext           // 아래로 찾기 버튼
    case findClose          // 찾기 바 닫기 버튼
    case findNoMatch        // 결과 없음 표시
    case menuFind           // 메뉴: 찾기…
    case menuFindNext       // 메뉴: 다음 찾기

    // 빠른 열기(⌘P)
    case menuQuickOpen          // 메뉴 항목
    case quickOpenPlaceholder   // 입력 placeholder
    case quickOpenHint          // 입력 전 안내
    case quickOpenNoMatch       // 결과 없음
    case quickOpenCount(Int)    // 결과 개수
    case quickOpenTruncated(Int) // 인덱스 상한 안내
    case quickOpenKeysHint      // 하단 키 안내

    // 폴더 전체 본문 검색(⇧⌘F)
    case menuContentSearch
    case contentSearchPlaceholder
    case contentSearchRun            // 검색 실행 버튼
    case contentSearchHint           // 입력 전 안내
    case contentSearchRunning        // 검색 중
    case contentSearchNoMatch(String)
    case contentSearchCount(Int)
    case contentSearchTruncated(Int)
    case contentSearchLine(Int)      // "12행"
    case contentSearchKeysHint

    // 시작 화면(열어둔 폴더 없음)
    case openFolderToStart
    case openFolderHint
    case welcomeTitle
    case welcomeBody
    case welcomeOpenFolder
    case welcomeDragHint
    case welcomeRecent
    case welcomeClearRecent
    case welcomeRemoveRecent
    case welcomeRestoreFailed
    case welcomeRestoreFailedHint

    // 메뉴바
    case menuFontLarger
    case menuFontSmaller
    case menuFontDefault
    case menuAddPanel
    case menuRemovePanel
    case menuFocusNext
    case menuFocusPrevious
    case menuOpenFolder
    case menuToggleEdit
    case menuSave
    case menuOpenInTerminal

    // 하단 Function Key 바 (Total Commander 스타일)
    case menuCommands  // 메뉴바의 Function Key 메뉴 제목
    case fkeyView      // F3
    case fkeyEdit      // F4
    case fkeyCopy      // F5
    case fkeyRename    // F6
    case fkeyNewFolder // F7
    case fkeyDelete    // F8

    // 파일 필터(트리 헤더 토글)
    case filterMarkdownOnly  // 토글 OFF 상태 툴팁: 현재 md만 보는 중
    case filterAllFiles      // 토글 ON 상태 툴팁: 현재 전체 보는 중

    // 트리 정렬
    case sortMenu
    case sortByName
    case sortByModified
    case sortBySize
    case sortAscending
    case sortDescending

    // 멀티 리네임 툴 (Total Commander MRT)
    case mrtMenu             // 메뉴 항목
    case mrtTitle
    case mrtTargetCount(Int)
    case mrtSearchReplace
    case mrtSearch
    case mrtReplace
    case mrtRegex
    case mrtCaseInsensitive
    case mrtAffix
    case mrtPrefix
    case mrtSuffix
    case mrtCase
    case mrtCaseKeep
    case mrtCaseLower
    case mrtCaseUpper
    case mrtCounter
    case mrtCounterEnable
    case mrtCounterStart
    case mrtCounterStep
    case mrtCounterPad
    case mrtCounterHint
    case mrtColOld
    case mrtColNew
    case mrtApply
    case mrtWillRename(Int)
    case mrtConflicts(Int)
    case mrtIssueEmpty
    case mrtIssueDuplicate
    case mrtIssueInvalid

    // 폴더 선택 패널
    case openPanelPrompt
    case openPanelMessage

    // 다이얼로그 공통
    case ok
    case cancel
    case moveToTrash
    case renameTitle
    case deleteTitle

    // 환경설정
    case settingsTitle
    case language
    case colorTheme

    // 라이선스 (Pro)
    // 환경설정 › 파일 접근 권한
    case accessSection
    case accessBody
    case accessOpenSettings
    case accessRestartHint

    case licenseSection      // 환경설정 섹션 제목
    case licenseKeyField     // 키 입력 필드 라벨/플레이스홀더
    case licenseActivate     // 활성화 버튼
    case licenseDeactivate   // 해제 버튼
    case licenseRefresh      // 재확인 버튼
    case licenseStatusPro    // 상태: Pro 활성
    case licenseStatusFree   // 상태: 무료
    case supportSection      // 후원 섹션 제목
    case githubSponsors      // GitHub Sponsors 링크 라벨
    case buyMeCoffee         // Buy Me a Coffee 링크 라벨
    case supportHint         // 후원 안내 문구

    // 단축키 도움말
    case shortcutsMenu       // Help 메뉴 항목
    case menuCheckForUpdates // Help 메뉴: 업데이트 확인
    case shortcutsTitle      // 창 제목
    case scCategoryFile      // 분류: 파일/트리
    case scCategoryViewer    // 분류: 뷰어
    case scCategoryPanel     // 분류: 패널/포커스
    case scCategoryFKeys     // 분류: Function 키
    case scCategoryMouse     // 분류: 마우스
    // 지원 파일 형식 창(Help ▸ 지원 파일 형식)
    case fileTypesMenu       // Help 메뉴 항목
    case fileTypesTitle      // 창 제목
    case ftMarkdown          // 마크다운
    case ftHTML              // HTML
    case ftPDF               // PDF
    case ftImage             // 이미지
    case ftRichDoc           // Office·iWork 문서
    case convertingDocument      // 서식 문서 → PDF 변환 중(헤더 표시)
    case convertingDocumentHelp  // 변환 중 표시의 툴팁
    case pageIndicatorHelp       // 쪽 표시("3 / 12")의 툴팁
    case useQuickLookLayout      // 렌더러 전환: 변환 PDF → QuickLook
    case useConvertedLayout      // 렌더러 전환: QuickLook → 변환 PDF
    case ftText              // 일반 텍스트
    case ftTextExtensions    // 텍스트 형식의 확장자 설명(전 확장자 나열 불가)
    case scNewFile
    case scNewFolder
    case scDelete
    case scOpenFolder
    case scOpenInTerminal
    case scQuickOpen
    case scContentSearch
    case scFind
    case scFindNext
    case scFindPrevious
    case scToggleEdit
    case scSave
    case scFontLarger
    case scFontSmaller
    case scFontReset
    case scZoomWheel         // PDF Cmd+휠 확대/축소
    case scToggleTerminal
    case scAddPanel
    case scRemovePanel
    case scFocusNext
    case scFocusPrev
    case scGoParent
    case scGoToFolder
    case scMultiRename
    case scMouseOpen         // 클릭: 열기
    case scMouseNewPanel     // Cmd+클릭: 새 패널
    case scMouseToggle       // Option+클릭: 선택 토글
    case scMouseRange        // Shift+클릭: 범위 선택
    case scMousePanelDrag    // 헤더 드래그: 패널 순서
    case scClose
    case madeBy              // 도움말 푸터: 만든이
    case menuAbout           // 앱 메뉴: Mac Commander 정보
    case youtubeChannel      // 유튜브 채널 링크 라벨
    case blogLink            // 블로그 링크 라벨
    case sourceCodeLink      // 소스 코드(GitHub) 링크 라벨

    // Pro 기능 안내(업셀 시트)
    case proMenu               // 도움말 메뉴: Pro 기능 안내 열기
    case proTitle              // 시트 제목
    case proIntro              // 메뉴에서 직접 열었을 때(특정 기능이 막힌 게 아닐 때) 첫 문장
    case proIncludes           // "Pro에 포함된 기능" 소제목
    case proOpenSettings       // 환경설정으로 이동 버튼
    case proBuy                // 체크아웃 열기 버튼
    case proMultiPanel         // 기능 이름: 뷰어 패널 분할
    case proMultiPanelDetail
    case proTerminal           // 기능 이름: 내장 터미널
    case proTerminalDetail
    case proMultiRename        // 기능 이름: 멀티 리네임
    case proMultiRenameDetail
    case proSuffix             // 메뉴 라벨에 붙이는 표시

    // 오픈소스 고지 (Help ▸ 오픈소스 라이선스)
    case ackMenu             // Help 메뉴 항목
    case ackTitle            // 시트 제목
    case ackFootnote         // 하단 안내(번들 구성요소는 추가 오픈소스를 포함할 수 있음)
    case ackMissingText      // 라이선스 전문을 못 읽었을 때

    // 동적 메시지(인자 포함)
    case proBlocked(String)  // "OOO은(는) Pro 기능입니다."
    case confirmDelete(String)
    case confirmDeleteMulti(Int)
    case cannotReadFile
    case alreadyExists(String)
    case invalidNameChars
    case existsInTarget(String)
    case createFailed(String)
    case saveFailed(String)
    case renameFailed(String)
    case moveFailed(String)
    case copyFailed(String)
    case deleteFailed(String)
    case newDocumentName     // "새 문서" / "New Document"
    case copySuffix          // " 사본" / " copy"

    // MARK: 상태바 (하단 정보)
    case statusFolder            // 폴더 항목 표시("폴더")
    case statusItemsCount(Int)   // 현재 폴더 항목 수("N개 항목")
    case statusSelected(Int, String)  // 선택 개수 + 총 크기("N개 선택 · 12.3 MB")
    case statusEmpty             // 항목이 없거나 커서 없음
    case statusIP(String)        // 로컬 IP 표시("IP 192.168.0.42")
    case statusIPUnavailable     // IP를 못 찾았을 때
    case statusIPCopyHint        // IP 툴팁(클릭하면 복사)
    case statusIPCopied(String)  // IP 복사됨 알림

    /// 동사(이동/복사) — moveFailed/copyFailed에 쓰임.
    func value(for lang: AppLanguage) -> String {
        let ko: String
        let en: String
        switch self {
        case .newMarkdownFile:  ko = "새 마크다운 파일"; en = "New Markdown File"
        case .newFolder:        ko = "새 폴더"; en = "New Folder"
        case .rename:           ko = "이름 변경"; en = "Rename"
        case .delete:           ko = "삭제"; en = "Delete"
        case .openInTerminal:   ko = "터미널에서 열기"; en = "Open in Terminal"
        case .copyPath:         ko = "경로 복사"; en = "Copy Path"
        case .copyRelativePath: ko = "상대 경로 복사"; en = "Copy Relative Path"
        case .enterFolder:      ko = "이 폴더로 진입"; en = "Enter This Folder"
        case .goToParent:       ko = "상위 폴더로"; en = "Go to Parent Folder"
        case .goToParentTooltip: ko = "상위 폴더로 (⌘↑)"; en = "Go to Parent Folder (⌘↑)"
        case .goToFolder:       ko = "폴더로 이동…"; en = "Go to Folder…"
        case .goToFolderTitle:  ko = "폴더로 이동"; en = "Go to Folder"
        case .goToFolderPrompt: ko = "이동할 폴더 또는 파일 경로를 입력하세요:"; en = "Enter the path to a folder or file:"
        case .goToFolderPlaceholder: ko = "/Users/…/폴더 또는 파일.md"; en = "/Users/…/folder or file.md"
        case .goToFolderInvalid: ko = "해당 경로를 찾을 수 없습니다."; en = "That path could not be found."
        case .goCancel:         ko = "취소"; en = "Cancel"
        case .goConfirm:        ko = "이동"; en = "Go"

        case .selectFilePrompt: ko = "왼쪽에서 마크다운 파일을 선택하세요"; en = "Select a Markdown file on the left"
        case .fontSmaller:      ko = "글자 작게 (⌘-)"; en = "Smaller Text (⌘-)"
        case .fontReset:        ko = "기본 크기로 (⌘0)"; en = "Default Size (⌘0)"
        case .fontLarger:       ko = "글자 크게 (⌘+)"; en = "Larger Text (⌘+)"
        case .addPanel:         ko = "패널 늘리기 (⌃⌘+)"; en = "Add Panel (⌃⌘+)"
        case .closePanel:       ko = "이 패널 닫기"; en = "Close This Panel"
        case .editDocument:     ko = "편집 (⌘E)"; en = "Edit (⌘E)"
        case .previewDocument:  ko = "미리보기 (⌘E)"; en = "Preview (⌘E)"
        case .saveDocument:     ko = "저장 (⌘S)"; en = "Save (⌘S)"
        case .unsavedBadge:     ko = "저장하지 않은 변경 사항"; en = "Unsaved changes"
        case .toggleTerminal:   ko = "터미널 (⌃`)"; en = "Terminal (⌃`)"
        case .launchClaudeCode: ko = "Claude Code 실행"; en = "Launch Claude Code"
        case .terminalTitle:    ko = "터미널"; en = "Terminal"
        case .terminalMoveBottom: ko = "터미널을 아래로"; en = "Move Terminal to Bottom"
        case .terminalMoveRight:  ko = "터미널을 오른쪽으로"; en = "Move Terminal to Right"
        case .zoomIn:           ko = "확대"; en = "Zoom In"
        case .zoomOut:          ko = "축소"; en = "Zoom Out"
        case .zoomReset:        ko = "폭 맞춤"; en = "Fit Width"
        case .zoomFit:          ko = "맞춤"; en = "Fit"

        case .findPlaceholder:  ko = "문서에서 찾기"; en = "Find in document"
        case .findPrevious:     ko = "위로 찾기 (⇧Enter)"; en = "Find Previous (⇧Enter)"
        case .findNext:         ko = "아래로 찾기 (Enter)"; en = "Find Next (Enter)"
        case .findClose:        ko = "찾기 닫기 (Esc)"; en = "Close Find (Esc)"
        case .findNoMatch:      ko = "결과 없음"; en = "No results"
        case .menuFind:         ko = "문서에서 찾기…"; en = "Find in Document…"
        case .menuFindNext:     ko = "다음 찾기"; en = "Find Next"

        case .menuQuickOpen:    ko = "파일 빠른 열기…"; en = "Quick Open File…"
        case .quickOpenPlaceholder: ko = "파일 이름으로 찾기"; en = "Find by file name"
        case .quickOpenHint:
            ko = "이름 일부를 입력하세요. 공백으로 나눠 여러 단어로 좁힐 수 있습니다."
            en = "Type part of a name. Separate words with spaces to narrow it down."
        case .quickOpenNoMatch: ko = "일치하는 파일이 없습니다"; en = "No matching files"
        case .quickOpenCount(let n):
            ko = "\(n)개 결과"; en = n == 1 ? "1 result" : "\(n) results"
        case .quickOpenTruncated(let n):
            ko = "파일이 많아 처음 \(n)개만 훑었습니다"
            en = "Too many files — only the first \(n) were indexed"
        case .quickOpenKeysHint: ko = "↑↓ 이동 · Enter 열기 · Esc 닫기"; en = "↑↓ move · Enter open · Esc close"

        case .menuContentSearch: ko = "폴더에서 찾기…"; en = "Find in Folder…"
        case .contentSearchPlaceholder: ko = "문서 본문에서 찾을 내용"; en = "Text to find in documents"
        case .contentSearchRun: ko = "찾기"; en = "Search"
        case .contentSearchHint:
            ko = "현재 폴더 아래 문서들의 본문을 찾습니다. 결과를 고르면 그 문서를 열고 같은 내용을 ⌘F로 이어 찾습니다."
            en = "Searches document text under the current folder. Picking a result opens that document and continues the search with ⌘F."
        case .contentSearchRunning: ko = "본문을 훑는 중…"; en = "Searching document text…"
        case .contentSearchNoMatch(let q):
            ko = "‘\(q)’를 담은 문서가 없습니다"; en = "No documents contain “\(q)”"
        case .contentSearchCount(let n):
            ko = "\(n)개 줄에서 발견"; en = n == 1 ? "1 matching line" : "\(n) matching lines"
        case .contentSearchTruncated(let n):
            ko = "결과가 많아 처음 \(n)개만 표시합니다"
            en = "Too many results — showing the first \(n)"
        case .contentSearchLine(let n): ko = "\(n)행"; en = "line \(n)"
        case .contentSearchKeysHint: ko = "↑↓ 이동 · Enter 검색 · 클릭하면 열기"; en = "↑↓ move · Enter search · click to open"

        case .openFolderToStart: ko = "폴더를 열어 시작하세요"; en = "Open a folder to get started"
        case .openFolderHint:    ko = "⌘O 또는 폴더를 여기로 드래그"; en = "⌘O or drag a folder here"
        case .welcomeTitle:     ko = "폴더를 열어 시작하세요"; en = "Open a folder to get started"
        case .welcomeBody:
            ko = "고른 폴더 안의 마크다운·PDF·이미지·HTML·Office·iWork 문서를 트리에서 훑어보고 오른쪽에서 바로 읽습니다. 고른 폴더 밖은 읽지 않습니다."
            en = "Browse the Markdown, PDF, image, HTML, Office, and iWork documents inside the folder you pick, and read them on the right. Nothing outside that folder is read."
        case .welcomeOpenFolder: ko = "폴더 열기"; en = "Open Folder"
        case .welcomeDragHint:  ko = "⌘O 또는 폴더를 창으로 끌어다 놓기"; en = "⌘O, or drag a folder onto the window"
        case .welcomeRecent:    ko = "최근 폴더"; en = "RECENT FOLDERS"
        case .welcomeClearRecent: ko = "목록 지우기"; en = "Clear"
        case .welcomeRemoveRecent: ko = "목록에서 제거"; en = "Remove from List"
        case .welcomeRestoreFailed:
            ko = "지난번에 열어둔 폴더를 다시 열 수 없습니다"
            en = "Could not reopen the folder from your last session"
        case .welcomeRestoreFailedHint:
            ko = "폴더가 지워졌거나 옮겨졌거나, 접근 권한이 사라졌을 수 있습니다. 폴더를 다시 열어주세요."
            en = "It may have been deleted, moved, or had its access revoked. Please open the folder again."

        case .menuFontLarger:   ko = "글자 크게"; en = "Larger Text"
        case .menuFontSmaller:  ko = "글자 작게"; en = "Smaller Text"
        case .menuFontDefault:  ko = "기본 글자 크기"; en = "Default Text Size"
        case .menuAddPanel:     ko = "뷰어 패널 늘리기"; en = "Add Viewer Panel"
        case .menuRemovePanel:  ko = "뷰어 패널 줄이기"; en = "Remove Viewer Panel"
        case .menuFocusNext:    ko = "다음 영역으로"; en = "Focus Next Area"
        case .menuFocusPrevious: ko = "이전 영역으로"; en = "Focus Previous Area"
        case .menuOpenFolder:   ko = "폴더 열기…"; en = "Open Folder…"
        case .menuToggleEdit:   ko = "편집/미리보기 전환"; en = "Toggle Edit/Preview"
        case .menuSave:         ko = "저장"; en = "Save"
        case .menuOpenInTerminal: ko = "터미널에서 열기"; en = "Open in Terminal"

        case .menuCommands:  ko = "명령"; en = "Commands"
        case .fkeyView:      ko = "보기"; en = "View"
        case .fkeyEdit:      ko = "편집"; en = "Edit"
        case .fkeyCopy:      ko = "복사"; en = "Copy"
        case .fkeyRename:    ko = "이름변경"; en = "Rename"
        case .fkeyNewFolder: ko = "새폴더"; en = "NewFolder"
        case .fkeyDelete:    ko = "삭제"; en = "Delete"

        case .filterMarkdownOnly: ko = "마크다운만 보기 (클릭: 전체 파일)"; en = "Markdown only (click for all files)"
        case .filterAllFiles:     ko = "전체 파일 보기 (클릭: 마크다운만)"; en = "All files (click for Markdown only)"

        case .sortMenu:         ko = "정렬"; en = "Sort"
        case .sortByName:       ko = "이름순"; en = "By Name"
        case .sortByModified:   ko = "수정일순"; en = "By Date Modified"
        case .sortBySize:       ko = "크기순"; en = "By Size"
        case .sortAscending:    ko = "오름차순으로"; en = "Sort Ascending"
        case .sortDescending:   ko = "내림차순으로"; en = "Sort Descending"

        case .mrtMenu:          ko = "멀티 리네임…"; en = "Multi-Rename…"
        case .mrtTitle:         ko = "멀티 리네임 툴"; en = "Multi-Rename Tool"
        case .mrtTargetCount(let n): ko = "대상 \(n)개"; en = "\(n) items"
        case .mrtSearchReplace: ko = "검색 → 치환"; en = "Search → Replace"
        case .mrtSearch:        ko = "검색"; en = "Search"
        case .mrtReplace:       ko = "치환"; en = "Replace"
        case .mrtRegex:         ko = "정규식 사용"; en = "Use regex"
        case .mrtCaseInsensitive: ko = "대소문자 무시"; en = "Ignore case"
        case .mrtAffix:         ko = "접두 / 접미사"; en = "Prefix / Suffix"
        case .mrtPrefix:        ko = "접두"; en = "Prefix"
        case .mrtSuffix:        ko = "접미"; en = "Suffix"
        case .mrtCase:          ko = "대소문자"; en = "Case"
        case .mrtCaseKeep:      ko = "그대로"; en = "Keep"
        case .mrtCaseLower:     ko = "소문자"; en = "lower"
        case .mrtCaseUpper:     ko = "대문자"; en = "UPPER"
        case .mrtCounter:       ko = "연번"; en = "Counter"
        case .mrtCounterEnable: ko = "연번 추가"; en = "Add counter"
        case .mrtCounterStart:  ko = "시작"; en = "Start"
        case .mrtCounterStep:   ko = "증분"; en = "Step"
        case .mrtCounterPad:    ko = "자릿수"; en = "Digits"
        case .mrtCounterHint:   ko = "이름에 {N}을 넣으면 그 위치에, 없으면 끝에 붙습니다."
                                en = "Put {N} in the name to place it, otherwise appended at the end."
        case .mrtColOld:        ko = "이전 이름"; en = "Old name"
        case .mrtColNew:        ko = "새 이름"; en = "New name"
        case .mrtApply:         ko = "적용"; en = "Apply"
        case .mrtWillRename(let n): ko = "\(n)개 이름 변경"; en = "Rename \(n)"
        case .mrtConflicts(let n):  ko = "충돌 \(n)개 — 해결 필요"; en = "\(n) conflicts — resolve first"
        case .mrtIssueEmpty:    ko = "이름이 비어 있음"; en = "Empty name"
        case .mrtIssueDuplicate: ko = "같은 폴더에 중복 이름"; en = "Duplicate name in folder"
        case .mrtIssueInvalid:  ko = "'/' 또는 ':' 포함"; en = "Contains '/' or ':'"

        case .openPanelPrompt:  ko = "열기"; en = "Open"
        case .openPanelMessage: ko = "마크다운 문서가 있는 폴더를 선택하세요"; en = "Choose a folder containing Markdown documents"

        case .ok:           ko = "확인"; en = "OK"
        case .cancel:       ko = "취소"; en = "Cancel"
        case .moveToTrash:  ko = "휴지통으로 이동"; en = "Move to Trash"
        case .renameTitle:  ko = "이름 변경"; en = "Rename"
        case .deleteTitle:  ko = "삭제"; en = "Delete"

        case .settingsTitle: ko = "환경설정"; en = "Preferences"
        case .language:      ko = "언어"; en = "Language"
        case .colorTheme:    ko = "색상 테마"; en = "Color Theme"
        case .accessSection:    ko = "파일 접근"; en = "File Access"
        case .accessBody:
            ko = "이 앱은 직접 고른 폴더만 읽습니다. 전체 디스크 접근은 필요하지 않지만, 데스크톱·문서·다운로드처럼 보호된 위치를 매번 승인 없이 열려면 켜 두는 편이 편합니다."
            en = "This app only reads folders you pick. Full Disk Access isn't required, but turning it on saves you from approving protected locations like Desktop, Documents, and Downloads each time."
        case .accessOpenSettings: ko = "시스템 설정에서 열기"; en = "Open in System Settings"
        case .accessRestartHint:
            ko = "권한을 바꾼 뒤에는 앱을 다시 시작해야 반영될 수 있습니다."
            en = "You may need to restart the app after changing this."

        case .licenseSection:   ko = "라이선스"; en = "License"
        case .licenseKeyField:  ko = "라이선스 키"; en = "License Key"
        case .licenseActivate:  ko = "활성화"; en = "Activate"
        case .licenseDeactivate: ko = "해제"; en = "Deactivate"
        case .licenseRefresh:   ko = "재확인"; en = "Refresh"
        case .licenseStatusPro: ko = "Pro 활성"; en = "Pro active"
        case .licenseStatusFree: ko = "무료 버전"; en = "Free version"
        case .supportSection:   ko = "후원"; en = "Support"
        case .githubSponsors:   ko = "💖 GitHub Sponsors로 후원하기"; en = "💖 Sponsor on GitHub"
        case .buyMeCoffee:      ko = "☕️ 커피 한 잔 후원하기"; en = "☕️ Buy me a coffee"
        case .supportHint:      ko = "개발에 도움이 됩니다. 감사합니다!"; en = "It helps development. Thank you!"

        case .shortcutsMenu:    ko = "키보드 단축키"; en = "Keyboard Shortcuts"
        case .menuCheckForUpdates: ko = "업데이트 확인…"; en = "Check for Updates…"
        case .shortcutsTitle:   ko = "단축키"; en = "Shortcuts"
        case .scCategoryFile:   ko = "파일 · 트리"; en = "File · Tree"
        case .scCategoryViewer: ko = "뷰어"; en = "Viewer"
        case .scCategoryPanel:  ko = "패널 · 포커스"; en = "Panel · Focus"
        case .scCategoryFKeys:  ko = "Function 키"; en = "Function Keys"
        case .scCategoryMouse:  ko = "마우스"; en = "Mouse"
        case .fileTypesMenu:    ko = "지원 파일 형식"; en = "Supported File Types"
        case .fileTypesTitle:   ko = "지원 파일 형식"; en = "Supported File Types"
        case .ftMarkdown:       ko = "마크다운 (수식·다이어그램 포함)"; en = "Markdown (math & diagrams)"
        case .ftHTML:           ko = "HTML 웹 문서"; en = "HTML web pages"
        case .ftPDF:            ko = "PDF 문서"; en = "PDF documents"
        case .ftImage:          ko = "이미지"; en = "Images"
        case .ftRichDoc:
            ko = "Office·iWork 문서 (읽기 전용)"
            en = "Office & iWork documents (read-only)"
        case .convertingDocument: ko = "정밀 변환 중"; en = "Refining"
        case .convertingDocumentHelp:
            ko = "레이아웃을 원본에 맞추는 중입니다. 끝나면 자동으로 바뀝니다."
            en = "Matching the original layout. The view updates when it finishes."
        case .pageIndicatorHelp: ko = "현재 쪽 / 전체 쪽"; en = "Current page / total pages"
        case .useQuickLookLayout:
            ko = "미리보기 방식으로 전환 — 사진이 잘리거나 칸이 비어 보일 때 쓰세요"
            en = "Switch to Quick Look — use when photos look clipped or cells appear empty"
        case .useConvertedLayout:
            ko = "정밀 레이아웃으로 전환 — 표 폭과 글꼴이 원본에 맞습니다"
            en = "Switch to the refined layout — matches the original table widths and fonts"
        case .ftText:           ko = "일반 텍스트 (로그·CSV·코드 등)"; en = "Plain text (logs, CSV, code…)"
        case .ftTextExtensions: ko = "그 외 모든 텍스트 파일 (.txt .csv .log .json …)"
                                en = "Any other text file (.txt .csv .log .json …)"
        case .scNewFile:        ko = "새 마크다운 파일"; en = "New Markdown File"
        case .scNewFolder:      ko = "새 폴더"; en = "New Folder"
        case .scDelete:         ko = "삭제(휴지통)"; en = "Delete (Trash)"
        case .scOpenFolder:     ko = "폴더 열기"; en = "Open Folder"
        case .scOpenInTerminal: ko = "시스템 터미널에서 열기"; en = "Open in System Terminal"
        case .scQuickOpen:      ko = "파일 빠른 열기"; en = "Quick Open File"
        case .scContentSearch:  ko = "폴더에서 본문 찾기"; en = "Find Text in Folder"
        case .scFind:           ko = "문서에서 찾기"; en = "Find in Document"
        case .scFindNext:       ko = "다음 결과로"; en = "Find Next"
        case .scFindPrevious:   ko = "이전 결과로"; en = "Find Previous"
        case .scToggleEdit:     ko = "편집/미리보기 전환"; en = "Toggle Edit / Preview"
        case .scSave:           ko = "저장"; en = "Save"
        case .scFontLarger:     ko = "글자 크게 (포커스한 영역)"; en = "Larger Text (focused area)"
        case .scFontSmaller:    ko = "글자 작게 (포커스한 영역)"; en = "Smaller Text (focused area)"
        case .scFontReset:      ko = "기본 글자 크기 (포커스한 영역)"; en = "Default Text Size (focused area)"
        case .scZoomWheel:      ko = "확대/축소 (마우스가 놓인 영역)"; en = "Zoom (area under the pointer)"
        case .scToggleTerminal: ko = "터미널 패널 열기/닫기"; en = "Toggle Terminal Panel"
        case .scAddPanel:       ko = "뷰어 패널 늘리기"; en = "Add Viewer Panel"
        case .scRemovePanel:    ko = "뷰어 패널 줄이기"; en = "Remove Viewer Panel"
        case .scFocusNext:      ko = "다음 영역으로 포커스"; en = "Focus Next Area"
        case .scFocusPrev:      ko = "이전 영역으로 포커스"; en = "Focus Previous Area"
        case .scGoParent:       ko = "상위 폴더로"; en = "Go to Parent Folder"
        case .scGoToFolder:     ko = "폴더로 이동"; en = "Go to Folder"
        case .scMultiRename:    ko = "멀티 리네임"; en = "Multi-Rename"
        case .scMouseOpen:      ko = "클릭: 활성 패널에 열기"; en = "Click: open in active panel"
        case .scMouseNewPanel:  ko = "Cmd+클릭: 새 패널에 열기"; en = "Cmd+Click: open in new panel"
        case .scMouseToggle:    ko = "Option+클릭: 선택 토글"; en = "Option+Click: toggle selection"
        case .scMouseRange:     ko = "Shift+클릭: 범위 선택"; en = "Shift+Click: range select"
        case .scMousePanelDrag: ko = "헤더 드래그: 패널 순서 바꾸기"; en = "Drag header: reorder panels"
        case .scClose:          ko = "닫기"; en = "Close"
        case .madeBy:           ko = "만든이"; en = "Made by"
        case .menuAbout:        ko = "Mac Commander 정보"; en = "About Mac Commander"
        case .youtubeChannel:   ko = "유튜브 채널"; en = "YouTube Channel"
        case .blogLink:         ko = "블로그"; en = "Blog"
        case .sourceCodeLink:   ko = "소스 코드"; en = "Source Code"

        case .proMenu:          ko = "Pro 기능 안내…"; en = "About Pro Features…"
        case .proTitle:         ko = "Pro 기능"; en = "Pro Feature"
        case .proIntro:
            ko = "무료 버전에서 트리 탐색, 뷰어, 편집과 저장, 파일 관리를 모두 쓸 수 있습니다. Pro는 아래 세 가지를 더 엽니다."
            en = "The free version includes tree browsing, the viewer, editing and saving, and file management. Pro adds these three."
        case .proIncludes:      ko = "PRO에 포함된 기능"; en = "INCLUDED IN PRO"
        case .proOpenSettings:  ko = "라이선스 키 입력…"; en = "Enter License Key…"
        case .proBuy:           ko = "Pro 구매하기"; en = "Buy Pro"
        case .proMultiPanel:    ko = "뷰어 패널 분할"; en = "Split Viewer Panels"
        case .proMultiPanelDetail:
            ko = "문서를 최대 3개까지 나란히 놓고 비교합니다."
            en = "Compare up to three documents side by side."
        case .proTerminal:      ko = "내장 터미널"; en = "Built-in Terminal"
        case .proTerminalDetail:
            ko = "보고 있는 폴더에서 셸을 열고 Claude Code를 실행합니다."
            en = "Open a shell in the current folder and launch Claude Code."
        case .proMultiRename:   ko = "멀티 리네임"; en = "Multi-Rename"
        case .proMultiRenameDetail:
            ko = "여러 파일 이름을 규칙으로 한 번에 바꿉니다."
            en = "Rename many files at once with a rule."
        case .proSuffix:        ko = "Pro"; en = "Pro"

        case .ackMenu:          ko = "오픈소스 라이선스…"; en = "Open Source Licenses…"
        case .ackTitle:         ko = "오픈소스 라이선스"; en = "Open Source Licenses"
        case .ackFootnote:
            ko = "일부 구성요소는 배포본에 다른 오픈소스를 함께 담고 있습니다. 전체 목록은 각 프로젝트 페이지를 참고하세요."
            en = "Some components bundle additional open source software. See each project's page for the full list."
        case .ackMissingText:   ko = "(라이선스 전문을 찾을 수 없습니다)"; en = "(License text not found)"

        case .proBlocked(let feature):
            ko = "'\(feature)'은(는) Pro 기능입니다. 무료 버전에서는 트리 탐색, 뷰어 1개, 편집과 저장, 파일 관리를 모두 쓸 수 있습니다."
            en = "\"\(feature)\" is a Pro feature. The free version includes tree browsing, one viewer, editing and saving, and file management."
        case .confirmDelete(let name):
            ko = "'\(name)'을(를) 휴지통으로 이동할까요?"
            en = "Move \"\(name)\" to the Trash?"
        case .confirmDeleteMulti(let count):
            ko = "선택한 \(count)개 항목을 휴지통으로 이동할까요?"
            en = "Move \(count) selected items to the Trash?"
        case .cannotReadFile: ko = "_(파일을 읽을 수 없습니다)_"; en = "_(Unable to read file)_"
        case .alreadyExists(let name):
            ko = "'\(name)'은(는) 이미 존재합니다."
            en = "\"\(name)\" already exists."
        case .invalidNameChars:
            ko = "이름에 '/' 또는 ':'는 사용할 수 없습니다."
            en = "Names cannot contain '/' or ':'."
        case .existsInTarget(let name):
            ko = "'\(name)'이(가) 대상 폴더에 이미 있습니다."
            en = "\"\(name)\" already exists in the target folder."
        case .createFailed(let e): ko = "생성 실패: \(e)"; en = "Create failed: \(e)"
        case .saveFailed(let e):   ko = "저장 실패: \(e)"; en = "Save failed: \(e)"
        case .renameFailed(let e): ko = "이름 변경 실패: \(e)"; en = "Rename failed: \(e)"
        case .moveFailed(let e):   ko = "이동 실패: \(e)"; en = "Move failed: \(e)"
        case .copyFailed(let e):   ko = "복사 실패: \(e)"; en = "Copy failed: \(e)"
        case .deleteFailed(let e): ko = "삭제 실패: \(e)"; en = "Delete failed: \(e)"
        case .newDocumentName:     ko = "새 문서"; en = "New Document"
        case .copySuffix:          ko = " 사본"; en = " copy"

        case .statusFolder:        ko = "폴더"; en = "Folder"
        case .statusItemsCount(let n): ko = "\(n)개 항목"; en = "\(n) items"
        case .statusSelected(let n, let size): ko = "\(n)개 선택 · \(size)"; en = "\(n) selected · \(size)"
        case .statusEmpty:         ko = "—"; en = "—"
        case .statusIP(let ip):    ko = "IP \(ip)"; en = "IP \(ip)"
        case .statusIPUnavailable: ko = "IP 없음"; en = "No IP"
        case .statusIPCopyHint:    ko = "클릭하면 IP 주소를 복사합니다"; en = "Click to copy IP address"
        case .statusIPCopied(let ip): ko = "IP 복사됨: \(ip)"; en = "IP copied: \(ip)"
        }
        return lang == .korean ? ko : en
    }
}

/// 뷰에서 간결하게 쓰기 위한 헬퍼.
/// 사용: `loc(.rename)` — LocalizationManager.shared를 @EnvironmentObject로 관찰.
extension View {
    func tr(_ key: L10n, _ manager: LocalizationManager) -> String {
        manager.string(key)
    }
}
