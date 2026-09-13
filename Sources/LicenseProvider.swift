import Foundation

/// 라이선스 키 검증 결과.
enum LicenseValidation: Equatable {
    /// 유효한 키. 표시용 이메일(있으면)과 만료일(있으면, 영구면 nil).
    case valid(email: String?, expiresAt: Date?)
    /// 키는 형식상 인식됐지만 유효하지 않음(폐기/환불/만료/한도초과 등). 사유 메시지.
    case invalid(reason: String)
    /// 검증 자체를 못 함(네트워크 오류 등). 온라인 재시도 대상 — Pro를 즉시 끄지 않음.
    case unreachable(reason: String)
}

/// 라이선스 키 활성화 결과.
///
/// 활성화는 검증과 다르다. 키 하나를 여러 기기에서 쓸 수 있으므로(현재 최대 5대)
/// 서버에 이 기기를 등록하고 `instanceId`를 받아 와야, 이후 검증과 해제를 기기 단위로 할 수 있다.
enum LicenseActivation: Equatable {
    /// 활성화 성공. instanceId는 이 기기의 등록 식별자로, 저장해 두었다가 검증·해제에 쓴다.
    case activated(instanceId: String?, email: String?, expiresAt: Date?)
    /// 서버가 명확히 거절함(없는 키, 폐기, 다른 상품 등).
    case rejected(reason: String)
    /// 활성화 한도를 다 씀. 다른 기기에서 해제하라고 안내해야 한다.
    case limitReached
    /// 서버에 닿지 못함. 사용자 잘못이 아니므로 키를 버리지 않는다.
    case unreachable(reason: String)
}

/// 라이선스 백엔드 추상화.
/// 결제 서비스에 종속되지 않도록 프로토콜로 분리한다. 서비스가 바뀌면 구현체만 갈아끼운다.
protocol LicenseProvider: Sendable {
    /// 이 기기를 등록하고 키를 활성화한다.
    func activate(key: String, instanceName: String) async -> LicenseActivation
    /// 키(와 등록된 기기)가 아직 유효한지 확인한다.
    func validate(key: String, instanceId: String?) async -> LicenseValidation
    /// 이 기기의 등록을 해제해 활성화 슬롯을 반납한다. 성공 여부를 돌려준다.
    func deactivate(key: String, instanceId: String) async -> Bool
}

// MARK: - 개발용 목 구현

/// 서비스 연동 전 개발·테스트용. "MC-PRO-"로 시작하는 키를 유효로 취급한다.
struct MockLicenseProvider: LicenseProvider {
    func activate(key: String, instanceName: String) async -> LicenseActivation {
        switch await validate(key: key, instanceId: nil) {
        case .valid(let email, let expiresAt):
            return .activated(instanceId: "mock-instance", email: email, expiresAt: expiresAt)
        case .invalid(let reason):
            return .rejected(reason: reason)
        case .unreachable(let reason):
            return .unreachable(reason: reason)
        }
    }

    func validate(key: String, instanceId: String?) async -> LicenseValidation {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid(reason: "empty key") }
        if trimmed.uppercased().hasPrefix("MC-PRO-") {
            return .valid(email: nil, expiresAt: nil)
        }
        return .invalid(reason: "unrecognized key")
    }

    func deactivate(key: String, instanceId: String) async -> Bool { true }
}

// MARK: - Creem 구현

/// Creem 라이선스를 쓰는 구현. 단, Creem API를 직접 부르지 않는다.
///
/// Creem의 라이선스 엔드포인트는 계정 전체를 조작할 수 있는 비밀 키를 요구하는데,
/// 배포된 앱 바이너리에 그 키를 넣으면 추출당한다. 그래서 Cloudflare Worker 프록시를
/// 사이에 두고, 앱은 비밀 없이 프록시만 호출한다. 프록시 소스는 비공개 리포(mac-commander-license-proxy)에 있다.
struct CreemLicenseProvider: LicenseProvider {
    /// 프록시 주소(라이선스 프록시를 배포한 Worker).
    /// 앱은 이 주소만 알면 되고, 테스트↔라이브 전환은 프록시 쪽 설정만 바꾸면 된다.
    static let proxyBase = URL(string: "https://mac-commander-license.maccommander.workers.dev")!

    /// 프록시 주소가 실제 값으로 채워졌는지.
    /// 자리표시자를 그대로 둔 채 배포되면 Pro가 조용히 죽는 대신 "연결 불가"로 드러난다.
    static var isConfigured: Bool { !proxyBase.absoluteString.contains("TODO-") }

    private var session: URLSession { .shared }

    func activate(key: String, instanceName: String) async -> LicenseActivation {
        let result = await post("activate", body: ["key": key, "instanceName": instanceName])
        switch result {
        case .failure(let reason):
            return .unreachable(reason: reason)
        case .success(let payload):
            guard payload.ok else {
                switch payload.error {
                case "activation_limit": return .limitReached
                case "unreachable", "rate_limited":
                    return .unreachable(reason: payload.error ?? "unreachable")
                default:
                    return .rejected(reason: payload.error ?? "invalid")
                }
            }
            guard payload.isActive else { return .rejected(reason: payload.status ?? "inactive") }
            return .activated(instanceId: payload.instanceId,
                              email: nil,
                              expiresAt: payload.expiresAtDate)
        }
    }

    func validate(key: String, instanceId: String?) async -> LicenseValidation {
        var body: [String: String] = ["key": key]
        if let instanceId { body["instanceId"] = instanceId }

        switch await post("validate", body: body) {
        case .failure(let reason):
            return .unreachable(reason: reason)
        case .success(let payload):
            guard payload.ok else {
                if payload.error == "unreachable" || payload.error == "rate_limited" {
                    return .unreachable(reason: payload.error ?? "unreachable")
                }
                return .invalid(reason: payload.error ?? "invalid")
            }
            guard payload.isActive else { return .invalid(reason: payload.status ?? "inactive") }
            return .valid(email: nil, expiresAt: payload.expiresAtDate)
        }
    }

    func deactivate(key: String, instanceId: String) async -> Bool {
        guard case .success(let payload) = await post("deactivate",
                                                      body: ["key": key, "instanceId": instanceId])
        else { return false }
        return payload.ok
    }

    // MARK: - 전송

    /// 프록시 응답. 오류는 코드 문자열로만 오므로 문구가 바뀌어도 앱 동작은 흔들리지 않는다.
    private struct ProxyResponse: Decodable {
        let ok: Bool
        let error: String?
        let status: String?
        let instanceId: String?
        let expiresAtDate: Date?

        /// Creem의 LicenseStatus 중 active만 Pro로 인정한다(inactive/expired/disabled는 제외).
        var isActive: Bool { status == nil || status == "active" }

        enum CodingKeys: String, CodingKey {
            case ok, error, status, instanceId, expiresAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
            error = try c.decodeIfPresent(String.self, forKey: .error)
            status = try c.decodeIfPresent(String.self, forKey: .status)
            instanceId = try c.decodeIfPresent(String.self, forKey: .instanceId)
            // 만료일 형식이 확정적이지 않다. 문자열(초 유무 둘 다)과 epoch 숫자를 모두 받아준다.
            // 여기서 실패해 응답 전체가 깨지면 정상 사용자가 무료로 떨어지므로 관대하게 읽는다.
            if let text = try? c.decodeIfPresent(String.self, forKey: .expiresAt) {
                expiresAtDate = Self.date(fromISO: text)
            } else if let epoch = try? c.decodeIfPresent(Double.self, forKey: .expiresAt) {
                expiresAtDate = Date(timeIntervalSince1970: epoch > 1e11 ? epoch / 1000 : epoch)
            } else {
                expiresAtDate = nil
            }
        }

        /// 소수점 이하 초가 있는 형식과 없는 형식을 모두 시도한다.
        private static func date(fromISO text: String) -> Date? {
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: text) { return date }
            return ISO8601DateFormatter().date(from: text)
        }
    }

    private enum PostResult {
        case success(ProxyResponse)
        case failure(String)
    }

    private func post(_ action: String, body: [String: String]) async -> PostResult {
        guard Self.isConfigured else { return .failure("proxy not configured") }

        var request = URLRequest(url: Self.proxyBase.appendingPathComponent(action))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await session.data(for: request)
            return .success(try JSONDecoder().decode(ProxyResponse.self, from: data))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
