import SwiftUI

/// 환경설정 창. 언어 + 색상 테마 + 라이선스.
struct PreferencesView: View {
    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var license: LicenseManager

    /// 키 입력 필드 초안.
    @State private var keyInput: String = ""

    var body: some View {
        Form {
            Picker(loc.string(.language), selection: $loc.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }

            Picker(loc.string(.colorTheme), selection: $theme.theme) {
                ForEach(AppTheme.allCases) { t in
                    Text(t.displayName(loc.language)).tag(t)
                }
            }

            accessSection
            if showsLicenseUI {
                licenseSection
            }
            supportSection
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 440)
        .navigationTitle(loc.string(.settingsTitle))
    }

    /// 파일 접근 권한 안내.
    ///
    /// 이 앱은 사용자가 직접 고른 폴더만 읽으므로 전체 디스크 접근은 **필수가 아니다**.
    /// 다만 데스크톱·문서·다운로드처럼 보호된 위치를 매번 승인 없이 오가려면 켜 두는 게 편하다.
    /// 앱이 대신 켜줄 수는 없어서 시스템 설정으로 데려다주는 것까지만 한다.
    @ViewBuilder
    private var accessSection: some View {
        Section(loc.string(.accessSection)) {
            Text(loc.string(.accessBody))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(loc.string(.accessOpenSettings)) {
                if let url = URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            Text(loc.string(.accessRestartHint))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 후원 섹션 — GitHub Sponsors · Buy Me a Coffee 자발적 후원 링크.
    @ViewBuilder
    private var supportSection: some View {
        Section(loc.string(.supportSection)) {
            Link(loc.string(.githubSponsors), destination: AppLinks.githubSponsors)
            Link(loc.string(.buyMeCoffee), destination: AppLinks.buyMeACoffee)
            Text(loc.string(.supportHint))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 라이선스 UI를 보여줄지.
    ///
    /// **살 수 있을 때만 Pro를 말한다**는 규칙을 화면에도 적용한 것이다. 구매 경로가 없는
    /// 상태에서 키 입력 필드를 띄우면 사용자는 존재하지 않는 상품을 찾아 나선다.
    /// 다만 이미 키를 활성화해 둔 사람에게는 확인·해제할 길을 남겨야 하므로 그때는 보여준다.
    private var showsLicenseUI: Bool {
        ProFeature.gatingEnabled || license.activeKey != nil
    }

    @ViewBuilder
    private var licenseSection: some View {
        Section(loc.string(.licenseSection)) {
            // 상태 표시.
            HStack {
                Image(systemName: license.isPro ? "checkmark.seal.fill" : "seal")
                    .foregroundStyle(license.isPro ? .green : .secondary)
                Text(license.isPro ? loc.string(.licenseStatusPro) : loc.string(.licenseStatusFree))
                Spacer()
                if license.isValidating { ProgressView().controlSize(.small) }
            }

            if license.isPro {
                // 활성화된 상태: 해제 / 재확인.
                HStack {
                    Button(loc.string(.licenseRefresh)) {
                        if let key = license.activeKey {
                            Task { await license.revalidate(key: key, silent: false) }
                        }
                    }
                    .disabled(license.activeKey == nil || license.isValidating)
                    Button(loc.string(.licenseDeactivate), role: .destructive) {
                        // 서버에 활성화 슬롯을 반납해야 해서 비동기가 됐다.
                        Task {
                            await license.deactivate()
                            keyInput = ""
                        }
                    }
                    .disabled(license.isValidating)
                }
            } else {
                // 무료 상태: 키 입력 + 활성화.
                TextField(loc.string(.licenseKeyField), text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(loc.string(.licenseActivate)) {
                        Task { await license.activate(key: keyInput) }
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty || license.isValidating)

                    // 키가 없는 사람은 여기서 바로 살 수 있어야 한다.
                    if let checkout = AppLinks.proCheckout {
                        Link(loc.string(.proBuy), destination: checkout)
                    }
                }
            }

            // 마지막 상태 메시지.
            if !license.statusMessage.isEmpty {
                Text(license.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
