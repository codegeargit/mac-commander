import SwiftUI

/// 색상 테마 종류.
enum AppTheme: String, CaseIterable, Identifiable {
    case `default`   // 레트로 Commander(다크 네이비 + 시안) — 앱 고유 정체성
    case dark        // 표준 다크(중립)
    case light       // 라이트
    case system      // macOS 설정에 따라 dark/light 자동

    var id: String { rawValue }

    func displayName(_ lang: AppLanguage) -> String {
        switch self {
        case .default: return lang == .korean ? "기본 (레트로)" : "Default (Retro)"
        case .dark:    return lang == .korean ? "다크" : "Dark"
        case .light:   return lang == .korean ? "라이트" : "Light"
        case .system:  return lang == .korean ? "시스템" : "System"
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
}

/// 앱 전역 테마 상태. @Published로 변경 시 뷰가 즉시 갱신된다.
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "app.theme") }
    }
    /// system 테마일 때 현재 시스템이 다크인지(뷰에서 갱신해 준다).
    @Published var systemIsDark: Bool = true

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "app.theme"),
           let t = AppTheme(rawValue: saved) {
            theme = t
        } else {
            theme = .default
        }
    }

    /// 현재 활성 색 모음.
    var colors: ColorSet {
        switch theme {
        case .default: return .retro
        case .dark:    return .dark
        case .light:   return .light
        case .system:  return systemIsDark ? .dark : .light
        }
    }

    /// 현재 테마가 어두운 계열인지(mermaid 등 WebView 렌더러의 테마 선택에 사용).
    var isDark: Bool {
        switch theme {
        case .default, .dark: return true
        case .light:          return false
        case .system:         return systemIsDark
        }
    }

    /// SwiftUI 창에 줄 색 구성(nil=시스템 따름).
    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .default, .dark: return .dark
        case .light:          return .light
        case .system:         return nil
        }
    }

    /// 현재 테마에 대응하는 임베디드 터미널 색(배경/전경/커서).
    /// SwiftTerm의 nativeBackgroundColor 등에 직접 넣을 NSColor를 돌려준다.
    /// 뷰어 배경/본문색과 톤을 맞춰 터미널이 앱에 자연스럽게 녹아들게 한다.
    var terminalColors: (background: NSColor, foreground: NSColor, cursor: NSColor) {
        let resolved: AppTheme = {
            if case .system = theme { return systemIsDark ? .dark : .light }
            return theme
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
