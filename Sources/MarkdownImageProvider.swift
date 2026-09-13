import SwiftUI
import AppKit
import MarkdownUI

/// 마크다운 본문의 이미지(`![](images/foo.png)`)를 표시하는 provider.
/// 기본 provider는 네트워크(NetworkImage) 전용이라 `file://` URL을 읽지 못해
/// 로컬 이미지가 조용히 사라진다. 로컬은 NSImage로 직접 읽고,
/// 원격(http/https)은 기본 provider에 그대로 위임한다.
struct LocalFileImageProvider: ImageProvider {
    @ViewBuilder
    func makeImage(url: URL?) -> some View {
        if let url, url.isFileURL {
            LocalMarkdownImage(url: url)
        } else {
            DefaultImageProvider().makeImage(url: url)
        }
    }
}

extension ImageProvider where Self == LocalFileImageProvider {
    /// 로컬 파일과 원격 URL을 모두 처리하는 이미지 provider.
    static var localFile: Self { .init() }
}

/// 로컬 이미지 한 장. 원본 픽셀 크기를 지키되, 패널보다 넓으면 폭에 맞춰 줄인다.
private struct LocalMarkdownImage: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            // NSImage.size는 DPI가 반영된 포인트 크기라 레티나 이미지가 과대/과소 표시될 수 있다.
            // 비트맵의 실제 픽셀 수를 2x(레티나) 기준으로 환산해 표시 크기를 정한다.
            let displayWidth = Self.displayWidth(of: image)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: displayWidth)
        } else {
            // 경로가 틀렸거나 못 읽는 경우: 조용히 사라지지 않도록 자리를 표시해 준다.
            Label(url.lastPathComponent, systemImage: "photo")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textMuted)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.codeBlockBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// 비트맵 픽셀 폭을 레티나(2x) 기준 포인트로 환산한다.
    /// 스크린샷은 대개 2x로 찍히므로 픽셀 그대로 쓰면 두 배로 커진다.
    private static func displayWidth(of image: NSImage) -> CGFloat {
        let pixelWidth = image.representations
            .map { CGFloat($0.pixelsWide) }
            .max() ?? image.size.width
        guard pixelWidth > 0 else { return image.size.width }
        return pixelWidth / 2
    }
}
