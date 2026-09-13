import SwiftUI
import Combine

/// 색상 테마 종류.
enum AppTheme: String, CaseIterable, Identifiable {
    case `default`   // 레트로 Commander(다크 네이비 + 시안) — 앱 고유 정체성
    case dark        // 표준 다크(중립)
    case light       // 라이트
    case system      // macOS 설정에 따라 dark/light 자동
    // 후원자 테마 — 후원자 키가 있을 때만 고를 수 있다. 다크 먼저, 라이트 나중(선택 목록 순서).
    case nord             // 차분한 청회색 다크
    case dracula          // 보라 강조 다크
    case gruvboxDark      // 따뜻한 갈색·노랑 레트로 다크
    case catppuccinMocha  // 파스텔 다크(핑크 강조)
    case everforestDark   // 숲 느낌의 초록 다크
    case solarizedLight   // 따뜻한 종이색 라이트
    case catppuccinLatte  // 파스텔 라이트(보라 강조)
    case rosePineDawn     // 장밋빛 라이트

    var id: String { rawValue }

    /// 후원자 키가 있어야 고를 수 있는 테마인지.
    ///
    /// 후원자 혜택은 기능이 아니라 꾸미기만 연다. 기본 테마 넷으로 앱은 이미 온전하다.
    var isSupporterOnly: Bool {
        switch self {
        case .default, .dark, .light, .system: return false
        case .nord, .dracula, .gruvboxDark, .catppuccinMocha, .everforestDark,
             .solarizedLight, .catppuccinLatte, .rosePineDawn: return true
        }
    }

    /// 후원자 테마 개수(안내 문구용). 테마를 늘려도 문구를 따로 고치지 않게 센다.
    static var supporterThemeCount: Int { allCases.filter(\.isSupporterOnly).count }

    func displayName(_ lang: AppLanguage) -> String {
        switch self {
        case .default: return lang == .korean ? "기본 (레트로)" : "Default (Retro)"
        case .dark:    return lang == .korean ? "다크" : "Dark"
        case .light:   return lang == .korean ? "라이트" : "Light"
        case .system:  return lang == .korean ? "시스템" : "System"
        case .nord:            return "Nord"
        case .dracula:         return "Dracula"
        case .gruvboxDark:     return "Gruvbox Dark"
        case .catppuccinMocha: return "Catppuccin Mocha"
        case .everforestDark:  return "Everforest Dark"
        case .solarizedLight:  return "Solarized Light"
        case .catppuccinLatte: return "Catppuccin Latte"
        case .rosePineDawn:    return "Rosé Pine Dawn"
        }
    }
}

/// 한 테마의 색 모음.
struct ColorSet {
    let panelBackground: Color
    let viewerBackground: Color
    let headerBackground: Color
    let headerBackgroundInactive: Color
    let accent: Color
    let accentDim: Color
    let textPrimary: Color
    /// 제목·볼드용. 본문(textPrimary)보다 한 단계 밝아(라이트에선 진해) 강조가 살아난다.
    let textHeading: Color
    let textFolder: Color
    let textMuted: Color
    let selectBackground: Color
    let selectForeground: Color
    let divider: Color
    let codeBlockBackground: Color
    let codeInlineBackground: Color
    /// 경고·실패 표시용(검색 결과 없음 등). 각 테마 배경에서 읽히는 붉은 계열.
    let textWarning: Color

    /// 기본(레트로 Commander) — 다크 네이비 + 시안.
    static let retro = ColorSet(
        panelBackground: Color(hex: 0x0A1A33),
        viewerBackground: Color(hex: 0x0D1117),
        headerBackground: Color(hex: 0x10325C),
        headerBackgroundInactive: Color(hex: 0x0C2342),
        accent: Color(hex: 0x33CCFF),
        accentDim: Color(hex: 0x2A6FB0),
        textPrimary: Color(hex: 0xC7D6EC),   // 순백을 피해 halation(글자 번짐)을 줄인다
        textHeading: Color(hex: 0xEAF3FF),
        textFolder: Color(hex: 0x7FE9FF),
        textMuted: Color(hex: 0x7A8CA3),
        selectBackground: Color(hex: 0x33CCFF),
        selectForeground: Color(hex: 0x06243F),
        divider: Color(hex: 0x1C2F4A),
        codeBlockBackground: Color(hex: 0x111B2E),
        codeInlineBackground: Color(hex: 0x16223A),
        textWarning: Color(hex: 0xFF7B72)
    )

    /// 표준 다크(중립 회색 + 블루 강조).
    static let dark = ColorSet(
        panelBackground: Color(hex: 0x1E1E1E),
        viewerBackground: Color(hex: 0x171717),
        headerBackground: Color(hex: 0x2A2A2C),
        headerBackgroundInactive: Color(hex: 0x232325),
        accent: Color(hex: 0x4AA3FF),
        accentDim: Color(hex: 0x3B6FA0),
        textPrimary: Color(hex: 0xCFCFCF),   // 순백을 피해 halation(글자 번짐)을 줄인다
        textHeading: Color(hex: 0xF2F2F2),
        textFolder: Color(hex: 0x9FD0FF),
        textMuted: Color(hex: 0x8A8A8E),
        selectBackground: Color(hex: 0x2F6FD0),
        selectForeground: Color(hex: 0xFFFFFF),
        divider: Color(hex: 0x3A3A3C),
        codeBlockBackground: Color(hex: 0x242424),
        codeInlineBackground: Color(hex: 0x2C2C2E),
        textWarning: Color(hex: 0xFF6961)
    )

    /// 라이트.
    static let light = ColorSet(
        panelBackground: Color(hex: 0xF2F3F5),
        viewerBackground: Color(hex: 0xFFFFFF),
        headerBackground: Color(hex: 0xE3E6EA),
        headerBackgroundInactive: Color(hex: 0xECEEF1),
        accent: Color(hex: 0x0A84FF),
        accentDim: Color(hex: 0x5AA9F0),
        textPrimary: Color(hex: 0x2E3338),   // 흰 배경에선 순검정보다 살짝 옅은 쪽이 편안하다
        textHeading: Color(hex: 0x0B0C0E),
        textFolder: Color(hex: 0x0A6BD0),
        textMuted: Color(hex: 0x8A8A8E),
        selectBackground: Color(hex: 0x0A84FF),
        selectForeground: Color(hex: 0xFFFFFF),
        divider: Color(hex: 0xD0D3D7),
        codeBlockBackground: Color(hex: 0xF0F1F3),
        codeInlineBackground: Color(hex: 0xF5F6F8),  // 흰 배경에 가깝게 — 아주 은은한 음영
        textWarning: Color(hex: 0xC9252D)
    )

    // MARK: 후원자 테마
    // 널리 쓰이는 공개 팔레트를 바탕으로, 이 앱의 역할(패널·헤더·선택)에 맞춰 배치했다.
    // 작은 글씨(흐린 텍스트·폴더명)는 원본 팔레트보다 한 단계 밝거나 진하게 잡아 대비를 확보한다.

    /// Nord — 차분한 청회색 다크.
    static let nord = ColorSet(
        panelBackground: Color(hex: 0x3B4252),
        viewerBackground: Color(hex: 0x2E3440),
        headerBackground: Color(hex: 0x434C5E),
        headerBackgroundInactive: Color(hex: 0x353B48),
        accent: Color(hex: 0x88C0D0),
        accentDim: Color(hex: 0x5E81AC),
        textPrimary: Color(hex: 0xD8DEE9),
        textHeading: Color(hex: 0xECEFF4),
        textFolder: Color(hex: 0x8FBCBB),
        textMuted: Color(hex: 0x8A96AD),
        selectBackground: Color(hex: 0x88C0D0),
        selectForeground: Color(hex: 0x2E3440),
        divider: Color(hex: 0x4C566A),
        codeBlockBackground: Color(hex: 0x353B48),
        codeInlineBackground: Color(hex: 0x3B4252),
        textWarning: Color(hex: 0xD57780)
    )

    /// Dracula — 보라 강조 다크.
    static let dracula = ColorSet(
        panelBackground: Color(hex: 0x21222C),
        viewerBackground: Color(hex: 0x282A36),
        headerBackground: Color(hex: 0x44475A),
        headerBackgroundInactive: Color(hex: 0x343746),
        accent: Color(hex: 0xBD93F9),
        accentDim: Color(hex: 0x6272A4),
        textPrimary: Color(hex: 0xE6E6E0),   // 원본 전경(#F8F8F2)보다 살짝 낮춰 글자 번짐을 줄인다
        textHeading: Color(hex: 0xF8F8F2),
        textFolder: Color(hex: 0x8BE9FD),
        textMuted: Color(hex: 0x8390BF),
        selectBackground: Color(hex: 0xBD93F9),
        selectForeground: Color(hex: 0x282A36),
        divider: Color(hex: 0x3A3D4D),
        codeBlockBackground: Color(hex: 0x21222C),
        codeInlineBackground: Color(hex: 0x343746),
        textWarning: Color(hex: 0xFF6E6E)
    )

    /// Gruvbox Dark — 따뜻한 갈색·노랑 레트로 다크.
    static let gruvboxDark = ColorSet(
        panelBackground: Color(hex: 0x32302F),
        viewerBackground: Color(hex: 0x282828),
        headerBackground: Color(hex: 0x504945),
        headerBackgroundInactive: Color(hex: 0x3C3836),
        accent: Color(hex: 0xFABD2F),
        accentDim: Color(hex: 0xD79921),
        textPrimary: Color(hex: 0xEBDBB2),
        textHeading: Color(hex: 0xFBF1C7),
        textFolder: Color(hex: 0x8EC07C),
        textMuted: Color(hex: 0xA89984),
        selectBackground: Color(hex: 0xFABD2F),
        selectForeground: Color(hex: 0x282828),
        divider: Color(hex: 0x45403D),
        codeBlockBackground: Color(hex: 0x32302F),
        codeInlineBackground: Color(hex: 0x3C3836),
        textWarning: Color(hex: 0xFB4934)
    )

    /// Catppuccin Mocha — 파스텔 다크, 핑크 강조.
    static let catppuccinMocha = ColorSet(
        panelBackground: Color(hex: 0x181825),
        viewerBackground: Color(hex: 0x1E1E2E),
        headerBackground: Color(hex: 0x313244),
        headerBackgroundInactive: Color(hex: 0x232334),
        accent: Color(hex: 0xF5C2E7),
        accentDim: Color(hex: 0x7F849C),
        textPrimary: Color(hex: 0xCDD6F4),
        textHeading: Color(hex: 0xF0F3FF),
        textFolder: Color(hex: 0x89DCEB),
        textMuted: Color(hex: 0x9399B2),
        selectBackground: Color(hex: 0xF5C2E7),
        selectForeground: Color(hex: 0x1E1E2E),
        divider: Color(hex: 0x313244),
        codeBlockBackground: Color(hex: 0x181825),
        codeInlineBackground: Color(hex: 0x313244),
        textWarning: Color(hex: 0xF38BA8)
    )

    /// Everforest Dark — 숲 느낌의 초록 다크.
    static let everforestDark = ColorSet(
        panelBackground: Color(hex: 0x232A2E),
        viewerBackground: Color(hex: 0x2D353B),
        headerBackground: Color(hex: 0x3D484D),
        headerBackgroundInactive: Color(hex: 0x343F44),
        accent: Color(hex: 0xA7C080),
        accentDim: Color(hex: 0x6F8A5C),
        textPrimary: Color(hex: 0xD3C6AA),
        textHeading: Color(hex: 0xE8DFC7),
        textFolder: Color(hex: 0x7FBBB3),
        textMuted: Color(hex: 0x9DA9A0),
        selectBackground: Color(hex: 0xA7C080),
        selectForeground: Color(hex: 0x2D353B),
        divider: Color(hex: 0x414B50),
        codeBlockBackground: Color(hex: 0x343F44),
        codeInlineBackground: Color(hex: 0x3D484D),
        textWarning: Color(hex: 0xE67E80)
    )

    /// Solarized Light — 따뜻한 종이색 라이트.
    static let solarizedLight = ColorSet(
        panelBackground: Color(hex: 0xEEE8D5),
        viewerBackground: Color(hex: 0xFDF6E3),
        headerBackground: Color(hex: 0xE4DCC4),
        headerBackgroundInactive: Color(hex: 0xEAE3CD),
        accent: Color(hex: 0x268BD2),
        accentDim: Color(hex: 0x7FB0D8),
        textPrimary: Color(hex: 0x586E75),   // 원본 본문색(#657B83)보다 한 단계 진하게
        textHeading: Color(hex: 0x073642),
        textFolder: Color(hex: 0x187069),
        textMuted: Color(hex: 0x6E7C7D),
        selectBackground: Color(hex: 0x268BD2),
        selectForeground: Color(hex: 0xFDF6E3),
        divider: Color(hex: 0xDDD6C1),
        codeBlockBackground: Color(hex: 0xEEE8D5),
        codeInlineBackground: Color(hex: 0xF2ECDA),
        textWarning: Color(hex: 0xDC322F)
    )

    /// Catppuccin Latte — 파스텔 라이트, 보라 강조.
    static let catppuccinLatte = ColorSet(
        panelBackground: Color(hex: 0xE6E9EF),
        viewerBackground: Color(hex: 0xEFF1F5),
        headerBackground: Color(hex: 0xDCE0E8),
        headerBackgroundInactive: Color(hex: 0xE2E5EB),
        accent: Color(hex: 0x8839EF),
        accentDim: Color(hex: 0xAE8AF5),
        textPrimary: Color(hex: 0x4C4F69),
        textHeading: Color(hex: 0x303246),
        textFolder: Color(hex: 0x1654D0),   // 원본 blue(#1E66F5)보다 진하게 — 패널 배경에서 대비 확보
        textMuted: Color(hex: 0x6C6F85),
        selectBackground: Color(hex: 0x8839EF),
        selectForeground: Color(hex: 0xEFF1F5),
        divider: Color(hex: 0xCCD0DA),
        codeBlockBackground: Color(hex: 0xE6E9EF),
        codeInlineBackground: Color(hex: 0xDCE0E8),
        textWarning: Color(hex: 0xD20F39)
    )

    /// Rosé Pine Dawn — 장밋빛이 도는 라이트.
    static let rosePineDawn = ColorSet(
        panelBackground: Color(hex: 0xF2E9E1),
        viewerBackground: Color(hex: 0xFAF4ED),
        headerBackground: Color(hex: 0xE7DDD4),
        headerBackgroundInactive: Color(hex: 0xEEE4DB),
        accent: Color(hex: 0xB4637A),
        accentDim: Color(hex: 0xD7827E),
        textPrimary: Color(hex: 0x575279),
        textHeading: Color(hex: 0x3E3A5C),
        textFolder: Color(hex: 0x286983),
        textMuted: Color(hex: 0x797593),
        selectBackground: Color(hex: 0xB4637A),
        selectForeground: Color(hex: 0xFAF4ED),
        divider: Color(hex: 0xDFDAD9),
        codeBlockBackground: Color(hex: 0xF4EDE8),
        codeInlineBackground: Color(hex: 0xEEE4DB),
        textWarning: Color(hex: 0xB03A2E)   // 강조색(장미색)과 구분되는 붉은 주황
    )
}

/// 앱 전역 테마 상태. @Published로 변경 시 뷰가 즉시 갱신된다.
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    /// 사용자가 고른 테마(저장값). 후원자 테마를 골랐더라도 키가 없으면 `effectiveTheme`은 기본으로 떨어진다.
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "app.theme") }
    }
    /// system 테마일 때 현재 시스템이 다크인지(뷰에서 갱신해 준다).
    @Published var systemIsDark: Bool = true
    /// 후원자 테마를 쓸 수 있는지. `LicenseManager.isSupporter`를 따라간다.
    @Published private(set) var supporterUnlocked: Bool = false

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "app.theme"),
           let t = AppTheme(rawValue: saved) {
            theme = t
        } else {
            theme = .default
        }
        LicenseManager.shared.$isSupporter
            .removeDuplicates()
            .assign(to: &$supporterUnlocked)
    }

    /// 실제로 그릴 테마.
    ///
    /// 키가 무효가 되면(환불·해제·만료) 후원자 테마 대신 기본 테마로 그린다. 저장값(`theme`)은
    /// 지우지 않으므로, 오프라인 유예가 끝났다가 다시 검증되면 고른 테마로 돌아온다.
    var effectiveTheme: AppTheme {
        theme.isSupporterOnly && !supporterUnlocked ? .default : theme
    }

    /// 테마 선택 목록. 후원자 테마는 키가 있을 때만 보인다.
    var selectableThemes: [AppTheme] {
        AppTheme.allCases.filter { !$0.isSupporterOnly || supporterUnlocked }
    }

    /// 현재 활성 색 모음.
    var colors: ColorSet {
        switch effectiveTheme {
        case .default: return .retro
        case .dark:    return .dark
        case .light:   return .light
        case .system:  return systemIsDark ? .dark : .light
        case .nord:            return .nord
        case .dracula:         return .dracula
        case .gruvboxDark:     return .gruvboxDark
        case .catppuccinMocha: return .catppuccinMocha
        case .everforestDark:  return .everforestDark
        case .solarizedLight:  return .solarizedLight
        case .catppuccinLatte: return .catppuccinLatte
        case .rosePineDawn:    return .rosePineDawn
        }
    }

    /// 현재 테마가 어두운 계열인지(mermaid 등 WebView 렌더러의 테마 선택에 사용).
    var isDark: Bool {
        switch effectiveTheme {
        case .default, .dark, .nord, .dracula, .gruvboxDark, .catppuccinMocha, .everforestDark:
            return true
        case .light, .solarizedLight, .catppuccinLatte, .rosePineDawn:
            return false
        case .system:
            return systemIsDark
        }
    }

    /// SwiftUI 창에 줄 색 구성(nil=시스템 따름).
    var preferredColorScheme: ColorScheme? {
        switch effectiveTheme {
        case .system: return nil
        default:      return isDark ? .dark : .light
        }
    }

    /// 현재 테마에 대응하는 임베디드 터미널 색(배경/전경/커서).
    /// SwiftTerm의 nativeBackgroundColor 등에 직접 넣을 NSColor를 돌려준다.
    /// 뷰어 배경/본문색과 톤을 맞춰 터미널이 앱에 자연스럽게 녹아들게 한다.
    var terminalColors: (background: NSColor, foreground: NSColor, cursor: NSColor) {
        let resolved: AppTheme = {
            if case .system = effectiveTheme { return systemIsDark ? .dark : .light }
            return effectiveTheme
        }()
        switch resolved {
        case .default:
            return (NSColor(hex: 0x0D1117), NSColor(hex: 0xE6F1FF), NSColor(hex: 0x33CCFF))
        case .dark:
            return (NSColor(hex: 0x171717), NSColor(hex: 0xEDEDED), NSColor(hex: 0x4AA3FF))
        case .light:
            return (NSColor(hex: 0xFFFFFF), NSColor(hex: 0x1C1C1E), NSColor(hex: 0x0A84FF))
        case .system:
            return (NSColor(hex: 0x171717), NSColor(hex: 0xEDEDED), NSColor(hex: 0x4AA3FF))
        case .nord:
            return (NSColor(hex: 0x2E3440), NSColor(hex: 0xD8DEE9), NSColor(hex: 0x88C0D0))
        case .dracula:
            return (NSColor(hex: 0x282A36), NSColor(hex: 0xF8F8F2), NSColor(hex: 0xBD93F9))
        case .gruvboxDark:
            return (NSColor(hex: 0x282828), NSColor(hex: 0xEBDBB2), NSColor(hex: 0xFABD2F))
        case .catppuccinMocha:
            return (NSColor(hex: 0x1E1E2E), NSColor(hex: 0xCDD6F4), NSColor(hex: 0xF5C2E7))
        case .everforestDark:
            return (NSColor(hex: 0x2D353B), NSColor(hex: 0xD3C6AA), NSColor(hex: 0xA7C080))
        case .solarizedLight:
            return (NSColor(hex: 0xFDF6E3), NSColor(hex: 0x586E75), NSColor(hex: 0x268BD2))
        case .catppuccinLatte:
            return (NSColor(hex: 0xEFF1F5), NSColor(hex: 0x4C4F69), NSColor(hex: 0x8839EF))
        case .rosePineDawn:
            return (NSColor(hex: 0xFAF4ED), NSColor(hex: 0x575279), NSColor(hex: 0xB4637A))
        }
    }
}

/// 디자인 토큰 접근점. 색은 현재 테마에서, 밀도 상수는 고정.
/// 뷰가 ThemeManager를 @EnvironmentObject로 관찰하므로 테마 변경 시 재읽기된다.
@MainActor
enum Palette {
    private static var c: ColorSet { ThemeManager.shared.colors }

    static var panelBackground: Color { c.panelBackground }
    static var viewerBackground: Color { c.viewerBackground }
    static var headerBackground: Color { c.headerBackground }
    static var headerBackgroundInactive: Color { c.headerBackgroundInactive }
    static var accent: Color { c.accent }
    static var accentDim: Color { c.accentDim }
    static var textPrimary: Color { c.textPrimary }
    static var textHeading: Color { c.textHeading }
    static var textFolder: Color { c.textFolder }
    static var textMuted: Color { c.textMuted }
    static var selectBackground: Color { c.selectBackground }
    static var selectForeground: Color { c.selectForeground }
    static var divider: Color { c.divider }
    static var codeBlockBackground: Color { c.codeBlockBackground }
    static var codeInlineBackground: Color { c.codeInlineBackground }
    static var textWarning: Color { c.textWarning }
    static var isDark: Bool { ThemeManager.shared.isDark }

    // 밀도(테마 무관 고정)
    static let rowHeight: CGFloat = Metrics.rowHeight
    static let treeFontSize: CGFloat = Metrics.treeFontSize
}

/// 테마와 무관한 레이아웃 상수(비격리).
enum Metrics {
    static let rowHeight: CGFloat = 21
    static let treeFontSize: CGFloat = 12.5
    /// 내장 터미널 기본 글자 크기.
    static let terminalFontSize: CGFloat = 12
    /// 마크다운 본문 최대 폭. 한 줄이 한글 45~55자에 들어와야 눈이 줄을 놓치지 않는다.
    /// 창이 이보다 넓으면 남는 공간은 좌우 여백이 된다.
    static let readingWidth: CGFloat = 760
}

extension Color {
    /// 0xRRGGBB 형태의 16진수로 Color 생성.
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

extension NSColor {
    /// 0xRRGGBB 형태의 16진수로 NSColor 생성(sRGB). 터미널 색 지정용.
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}
