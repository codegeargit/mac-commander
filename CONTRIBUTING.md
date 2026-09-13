# 기여 안내 / Contributing

Mac Commander에 관심 가져 주셔서 고맙습니다.

## 한국어

### 시작 전에

- **버그 제보·기능 제안**은 [이슈](https://github.com/codegeargit/mac-commander/issues)로 먼저 남겨 주세요. 큰 변경은 PR 전에 이슈에서 방향을 맞추면 헛수고를 줄일 수 있습니다
- 보안 문제는 공개 이슈 대신 GitHub의 **Security ▸ Report a vulnerability**로 알려 주세요

### 기여자 라이선스 계약(CLA)

처음 PR을 올리면 CLA 봇이 [CLA](CLA.md) 서명을 요청하는 댓글을 답니다. 봇이 안내하는 문구를 PR에 댓글로 남기면 서명이 끝나고, 이후 PR에는 다시 묻지 않습니다.

CLA에 동의하지 않은 PR은 병합할 수 없습니다. CLA는 기여물의 저작권을 넘기는 것이 아니라, 프로젝트가 기여물을 GPLv3 외의 조건으로도 배포할 수 있도록 사용을 허락하는 계약입니다.

### 개발 환경

[README의 빌드 방법](README.md#직접-빌드하기)을 따르세요. 요약하면 `xcodegen generate` 후 Xcode로 열면 됩니다.

### PR 작성

- 한 PR에는 한 가지 변경만 담아 주세요
- 주변 코드의 스타일(이름 짓기, 주석 밀도, SwiftUI 관용구)을 따라 주세요
- 화면이 바뀌는 변경이면 스크린샷을 첨부해 주세요
- 사용자에게 보이는 문구는 한국어와 영어를 함께 넣어 주세요(`Sources/Localization.swift`)
- `Sources/Info.plist`와 `.xcodeproj`는 `project.yml`에서 생성되므로 직접 고치지 않습니다

---

## English

### Before you start

- Please open an [issue](https://github.com/codegeargit/mac-commander/issues) for bug reports and feature ideas. For larger changes, agree on the approach in an issue before sending a PR
- Report security problems through GitHub's **Security ▸ Report a vulnerability** instead of a public issue

### Contributor License Agreement

On your first pull request, a CLA bot will ask you to sign the [CLA](CLA.md). Post the comment it asks for on the PR and you are done; later PRs will not ask again.

Pull requests cannot be merged until the CLA is signed. The CLA does not transfer your copyright; it grants the project permission to distribute your contribution, including under terms other than GPLv3.

### Development setup

Follow the [build instructions in the README](README.md#직접-빌드하기): run `xcodegen generate`, then open the project in Xcode.

### Pull requests

- Keep each PR to a single change
- Match the style of the surrounding code (naming, comment density, SwiftUI idioms)
- Attach screenshots for visible UI changes
- Provide both Korean and English for user-facing strings (`Sources/Localization.swift`)
- Do not edit `Sources/Info.plist` or the `.xcodeproj` directly; both are generated from `project.yml`
