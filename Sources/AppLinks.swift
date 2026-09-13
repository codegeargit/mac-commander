import Foundation

/// 앱 곳곳(도움말 푸터, About 패널, 환경설정)에서 쓰는 외부 링크 모음.
/// 주소가 바뀌면 여기만 고친다.
enum AppLinks {
    /// 제작자 GitHub. 만든이 이름에 걸리는 대표 링크.
    static let github = URL(string: "https://github.com/codegeargit")!
    /// 소스 코드(GPLv3). 바이너리를 배포하므로 대응 소스를 받을 곳을 앱 안에서도 알린다.
    static let sourceCode = URL(string: "https://github.com/codegeargit/mac-commander")!
    /// 후원 링크.
    static let githubSponsors = URL(string: "https://github.com/sponsors/codegeargit")!
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/codegear")!

    /// Pro 구매(체크아웃) 주소. 없으면 구매 버튼이 아예 표시되지 않는다.
    ///
    /// Creem은 테스트와 라이브의 상품이 별개라 주소가 다르다. 테스트 링크가 실판매 빌드에
    /// 섞이면 고객이 테스트 카드로 결제하고 아무것도 못 받는 사고가 나므로 빌드별로 분리한다.
    static let proCheckout: URL? = {
        #if DEBUG
        return URL(string: "https://www.creem.io/test/payment/prod_5iWRKUMyFQgMtgZjEozSh4")
        #else
        // 라이브 상품을 만든 뒤 주소를 채운다. 그전까지는 키 입력 안내만 나간다.
        return nil
        #endif
    }()
    /// 유튜브 채널.
    static let youtube: URL? = URL(string: "https://www.youtube.com/@codegear-21")
    /// 티스토리 블로그.
    static let blog: URL? = URL(string: "https://codegear.tistory.com/")

    /// 만든이 표기 옆에 덧붙이는 링크들. 주소가 채워진 것만 나온다.
    /// 도움말 푸터와 About 패널이 같은 목록을 쓴다.
    static var extras: [(label: L10n, url: URL)] {
        var out: [(label: L10n, url: URL)] = [(.sourceCodeLink, sourceCode)]
        if let youtube { out.append((.youtubeChannel, youtube)) }
        if let blog { out.append((.blogLink, blog)) }
        return out
    }
}
