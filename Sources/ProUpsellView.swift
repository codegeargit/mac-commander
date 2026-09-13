import SwiftUI

/// 무료 사용자가 Pro 기능을 건드렸을 때 뜨는 안내 시트.
///
/// 막혔다는 사실만 알리지 않고 Pro가 무엇을 여는지 함께 보여준다.
/// 결제 페이지는 아직 없으므로 구매 버튼 대신 환경설정(라이선스 키 입력)으로 안내한다.
struct ProUpsellView: View {
    /// 사용자가 방금 시도한 기능. 목록에서 강조 표시한다.
    /// nil이면 잠긴 기능을 누른 게 아니라 메뉴에서 직접 연 소개 모드다.
    let feature: ProFeature?

    @EnvironmentObject private var loc: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 헤더 (다른 시트들과 동일한 구성)
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Palette.accent)
                Text(loc.string(.proTitle))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(loc.string(.scClose)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Palette.headerBackground)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text(feature.map { loc.string(.proBlocked(loc.string($0.title))) }
                     ?? loc.string(.proIntro))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text(loc.string(.proIncludes))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)

                // Pro에 들어가는 기능 전체. 방금 막힌 항목은 강조해서 맥락을 잇는다.
                ForEach(ProFeature.allCases) { item in
                    let isCurrent = (item == feature)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(isCurrent ? Palette.accent : Palette.textMuted)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.string(item.title))
                                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                                .foregroundStyle(Palette.textPrimary)
                            Text(loc.string(item.detail))
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Spacer()
                    // 키를 이미 가진 사람은 곧바로 넣을 수 있게 환경설정으로 보낸다.
                    SettingsLink {
                        Text(loc.string(.proOpenSettings))
                    }
                    .simultaneousGesture(TapGesture().onEnded { dismiss() })

                    // 아직 살 곳이 없는 빌드(라이브 상품 미개설)에서는 버튼을 내보내지 않는다.
                    if let checkout = AppLinks.proCheckout {
                        Link(loc.string(.proBuy), destination: checkout)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Palette.viewerBackground)
        }
        .frame(width: 420, height: 330)
    }
}
