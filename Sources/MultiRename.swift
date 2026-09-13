import Foundation

/// 멀티 리네임 규칙 집합. 각 파일명에 순서대로 적용해 새 이름을 만든다.
/// (Total Commander Multi-Rename Tool의 실용 핵심 5가지)
struct RenameRule {
    /// 검색→치환.
    var search: String = ""
    var replace: String = ""
    var useRegex: Bool = false
    var caseInsensitive: Bool = false

    /// 대소문자 변환.
    enum CaseMode: String, CaseIterable, Identifiable {
        case keep      // 그대로
        case lower     // 소문자
        case upper     // 대문자
        var id: String { rawValue }
    }
    var caseMode: CaseMode = .keep

    /// 접두/접미사.
    var prefix: String = ""
    var suffix: String = ""

    /// 연번(카운터).
    var counterEnabled: Bool = false
    var counterStart: Int = 1
    var counterStep: Int = 1
    var counterPadding: Int = 2   // 자릿수(0 채움). 예: 2 → 01, 02
    /// 연번 삽입 위치 토큰. 이름 어딘가에 "{N}"이 있으면 그 자리에,
    /// 없으면 (counterEnabled일 때) 접미사로 끝에 붙는다.
    static let counterToken = "{N}"

    /// 규칙이 하나라도 실제 변화를 주는지(전부 비어 있으면 미적용).
    var isNoop: Bool {
        search.isEmpty && prefix.isEmpty && suffix.isEmpty
            && caseMode == .keep && !counterEnabled
    }
}

/// 멀티 리네임 계산 결과 한 줄.
struct RenamePreviewItem: Identifiable {
    let id: URL
    let url: URL
    let oldName: String
    let newName: String
    /// 이름이 바뀌었는지.
    var changed: Bool { oldName != newName }
    /// 충돌/오류 사유(없으면 nil) — 빈 이름, 결과 이름 중복 등.
    var issue: RenameIssue?
}

enum RenameIssue: Equatable {
    case emptyName          // 결과 이름이 비었음
    case duplicate          // 같은 폴더 내 다른 결과와 충돌
    case invalidChars       // '/' 또는 ':' 포함
}

enum MultiRename {
    /// 파일명에서 (이름, 확장자) 분리. 확장자 없으면 ext는 빈 문자열.
    /// 확장자는 변환에서 제외하고 끝에 다시 붙인다.
    private static func split(_ fileName: String) -> (stem: String, ext: String) {
        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension
        if ext.isEmpty { return (fileName, "") }
        let stem = String(fileName.dropLast(ext.count + 1))  // +1 for the dot
        return (stem, ext)
    }

    /// 한 이름(stem)에 규칙 적용. 연번 값(seq)은 호출 측에서 계산해 전달.
    private static func transformStem(_ stem: String, rule: RenameRule, sequence: Int?) -> String {
        var s = stem

        // 1) 검색 → 치환
        if !rule.search.isEmpty {
            if rule.useRegex {
                var options: NSRegularExpression.Options = []
                if rule.caseInsensitive { options.insert(.caseInsensitive) }
                if let re = try? NSRegularExpression(pattern: rule.search, options: options) {
                    let range = NSRange(s.startIndex..., in: s)
                    s = re.stringByReplacingMatches(in: s, options: [], range: range,
                                                    withTemplate: rule.replace)
                }
                // 잘못된 정규식이면 원본 유지(미리보기에서 무변경으로 보임).
            } else {
                let opts: String.CompareOptions = rule.caseInsensitive ? [.caseInsensitive] : []
                s = s.replacingOccurrences(of: rule.search, with: rule.replace, options: opts)
            }
        }

        // 2) 대소문자
        switch rule.caseMode {
        case .keep:  break
        case .lower: s = s.lowercased()
        case .upper: s = s.uppercased()
        }

        // 3) 연번 토큰 치환(또는 미사용)
        if let seq = sequence {
            let num = String(format: "%0\(max(rule.counterPadding, 1))d", seq)
            if s.contains(RenameRule.counterToken) {
                s = s.replacingOccurrences(of: RenameRule.counterToken, with: num)
            } else {
                s += num   // 토큰이 없으면 접미로
            }
        } else {
            // 연번 비활성: 혹시 남아 있는 토큰은 제거.
            s = s.replacingOccurrences(of: RenameRule.counterToken, with: "")
        }

        // 4) 접두/접미사
        s = rule.prefix + s + rule.suffix

        return s
    }

    /// 대상 URL 목록에 규칙을 적용해 미리보기 항목들을 만든다.
    /// urls는 표시 순서대로 전달(연번이 그 순서를 따름).
    static func preview(urls: [URL], rule: RenameRule) -> [RenamePreviewItem] {
        var items: [RenamePreviewItem] = []
        // 폴더별 결과 이름 집계로 중복 충돌 검출.
        var seenByDir: [URL: [String: Int]] = [:]

        var seq = rule.counterStart
        for url in urls {
            let oldName = url.lastPathComponent
            let (stem, ext) = split(oldName)

            let newStem = transformStem(
                stem, rule: rule,
                sequence: rule.counterEnabled ? seq : nil
            )
            if rule.counterEnabled { seq += rule.counterStep }

            let newName = ext.isEmpty ? newStem : "\(newStem).\(ext)"
            let dir = url.deletingLastPathComponent()
            seenByDir[dir, default: [:]][newName, default: 0] += 1

            items.append(RenamePreviewItem(id: url, url: url,
                                           oldName: oldName, newName: newName,
                                           issue: nil))
        }

        // 2차 패스: 충돌/오류 판정.
        for i in items.indices {
            let it = items[i]
            let dir = it.url.deletingLastPathComponent()
            let trimmed = it.newName.trimmingCharacters(in: .whitespaces)
            let stemOnly = split(it.newName).stem
            if trimmed.isEmpty || stemOnly.isEmpty {
                items[i].issue = .emptyName
            } else if it.newName.contains("/") || it.newName.contains(":") {
                items[i].issue = .invalidChars
            } else if (seenByDir[dir]?[it.newName] ?? 0) > 1 {
                items[i].issue = .duplicate
            }
        }
        return items
    }
}
