# 상표 및 로고 정책 / Trademark Policy

## 한국어

Mac Commander의 **소스 코드**는 [GNU GPL v3](LICENSE)로 공개되어 있어, 누구나 라이선스 조건에 따라 사용·수정·재배포할 수 있습니다.

다만 GPL은 저작권에 대한 허락일 뿐 **이름과 로고에 대한 권리는 주지 않습니다**(GPLv3 제7조 e항). 사용자가 공식 배포판과 수정판을 헷갈리지 않도록 아래 정책을 둡니다.

### 대상

- **"Mac Commander"** 이름
- **앱 아이콘과 로고 이미지**
  - `Sources/Assets.xcassets/AppIcon.appiconset/` 안의 이미지
  - `site/icon.png`

이 이미지 파일들은 GPL 적용 대상이 아니며, 저작권은 CodeGear에 있습니다(All rights reserved).

`Sources/Assets.xcassets/ClaudeIcon.imageset/`의 Claude 로고는 Anthropic의 상표이며, 이 리포의 어떤 라이선스로도 허락되지 않습니다.

### 허용되는 것

- 수정하지 않은 공식 배포판(dmg)을 그대로 재배포하는 것
- 이 프로젝트를 가리키거나 설명하기 위해 이름을 쓰는 것(예: "Mac Commander 기반", "Mac Commander용 플러그인")
- 이 리포를 빌드해 개인적으로 쓰는 것

### 허락이 필요한 것

소스를 **수정해서 배포**한다면(포크 포함) 다음을 지켜 주세요.

- 앱 이름을 "Mac Commander"가 아닌 다른 이름으로 바꿉니다. 혼동을 줄 만큼 비슷한 이름도 피해 주세요
- 앱 아이콘과 로고를 다른 이미지로 바꿉니다
- 번들 ID(`ai.codegear.MacCommander`)와 자동 업데이트 주소(`SUFeedURL`, `SUPublicEDKey`)를 본인 것으로 바꿉니다. 그대로 두면 공식 업데이트가 수정판을 덮어쓰거나 업데이트가 실패합니다
- 공식 배포판이나 CodeGear가 만든 것처럼 보이게 하지 않습니다

이 범위를 벗어나는 사용은 [이슈](https://github.com/codegeargit/mac-commander/issues)로 문의해 주세요.

---

## English

The **source code** of Mac Commander is released under the [GNU GPL v3](LICENSE). You may use, modify, and redistribute it under those terms.

The GPL is a copyright license and **does not grant rights to the project's name or logos** (GPLv3 section 7(e)). This policy exists so users can tell official builds apart from modified ones.

### Covered marks

- The name **"Mac Commander"**
- **The app icon and logo images**
  - images in `Sources/Assets.xcassets/AppIcon.appiconset/`
  - `site/icon.png`

These image files are not licensed under the GPL. They are copyright CodeGear, all rights reserved.

The Claude logo in `Sources/Assets.xcassets/ClaudeIcon.imageset/` is a trademark of Anthropic and is not licensed under any license in this repository.

### Allowed without permission

- Redistributing unmodified official builds (dmg)
- Using the name to refer to or describe this project (e.g. "based on Mac Commander", "a plugin for Mac Commander")
- Building this repository for your own use

### If you distribute a modified version

If you **distribute modified builds**, including forks:

- Use a different app name that is not confusingly similar to "Mac Commander"
- Replace the app icon and logos
- Change the bundle identifier (`ai.codegear.MacCommander`) and the update feed settings (`SUFeedURL`, `SUPublicEDKey`), so official updates neither overwrite your build nor fail against it
- Do not suggest that your build is official or endorsed by CodeGear

For any other use, please ask in an [issue](https://github.com/codegeargit/mac-commander/issues).
