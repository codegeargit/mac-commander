import Foundation
import Security

/// 후원자 키 상태의 단일 출처.
///
/// 후원자 키는 **기능을 잠그지 않는다.** 앱 기능은 키 유무와 무관하게 전부 무료이고,
/// 키는 후원자 혜택을 여는 데만 쓴다. 키는 Keychain에 저장하고, 앱 시작 시 서버로 재검증한다.
/// 오프라인·서버 오류 시엔 마지막 성공 시각 기준 유예 기간 동안 후원자 상태를 유지한다.
///
/// Keychain·UserDefaults의 저장 이름은 Pro 라이선스 시절의 것을 그대로 쓴다.
/// 바꾸면 이미 활성화해 둔 키를 잃는다. 개발 빌드만 이름 뒤에 `.debug`를 붙인다(`Key.suffix`).
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    /// 유효한 후원자 키가 활성화돼 있는지(후원자 혜택의 기준).
    @Published private(set) var isSupporter: Bool = false
    /// 마지막 검증 상태 메시지(UI 표시용).
    @Published private(set) var statusMessage: String = ""
    /// 검증 진행 중 여부(버튼 비활성/스피너용).
    @Published private(set) var isValidating: Bool = false
    /// 저장된(활성화된) 후원자 키. 없으면 nil.
    @Published private(set) var activeKey: String?

    private let provider: LicenseProvider
    private let defaults = UserDefaults.standard

    private enum Key {
        /// 개발 빌드는 테스트 키·테스트 프록시를 쓰므로 저장 이름 뒤에 붙여 릴리스의 라이브 키와 나눈다.
        /// 같은 Mac에서 두 빌드를 번갈아 실행해도 서로의 키와 기기 등록을 건드리지 않는다.
        /// 서명이 다른 빌드가 만든 키체인 항목을 읽으려다 암호 창이 뜨는 일도 막는다.
        #if DEBUG
        static let suffix = ".debug"
        #else
        static let suffix = ""
        #endif

        static let lastValidated = "license.lastValidatedAt" + suffix  // Date
        static let cachedEmail   = "license.email" + suffix            // String?
        /// 활성화 때 서버가 준 이 기기의 등록 식별자. 비밀이 아니라 기기 구분용이다.
        static let instanceId    = "license.instanceId" + suffix        // String?
    }

    /// 서버에 등록된 이 기기의 식별자. 검증과 해제에 쓴다.
    private var instanceId: String? {
        get { defaults.string(forKey: Key.instanceId) }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.instanceId) }
            else { defaults.removeObject(forKey: Key.instanceId) }
        }
    }

    /// 서버에 등록할 기기 이름. 사용자가 대시보드에서 자기 맥을 알아볼 수 있어야 한다.
    private var instanceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }
    /// Keychain 아이템 식별.
    private static let keychainService = "ai.codegear.MacCommander.license" + Key.suffix
    private static let keychainAccount = "licenseKey"

    /// 오프라인/서버오류 시 후원자 상태를 유지해 주는 유예 기간(마지막 성공 검증 이후).
    private static let offlineGrace: TimeInterval = 14 * 24 * 60 * 60  // 14일

    init(provider: LicenseProvider? = nil) {
        self.provider = provider ?? Self.defaultProvider
        self.activeKey = Self.readKeyFromKeychain()
        // 창이 뜨기 전에 잠정 상태를 정해 둔다. `restore()`(창의 onAppear)까지 기다리면
        // 후원자 테마를 쓰는 사람의 첫 화면이 기본 테마로 한 번 번쩍인다.
        self.isSupporter = activeKey != nil && withinOfflineGrace()
    }

    /// 프록시 주소가 실제 값으로 채워져 있으면 Creem을 쓰고, 아니면 개발용 목으로 남는다.
    /// 배포 주소를 넣는 순간 별도 설정 없이 실제 검증으로 전환된다.
    private static var defaultProvider: LicenseProvider {
        CreemLicenseProvider.isConfigured ? CreemLicenseProvider() : MockLicenseProvider()
    }

    // MARK: - 시작 시 복원/재검증

    /// 앱 시작 시 호출. 저장된 키가 있으면 조용히 재검증한다.
    ///
    /// 기능을 잠그지 않으므로 개발 빌드에서 후원자 상태를 강제로 켜 둘 이유가 없다.
    /// 개발 빌드는 테스트 체크아웃·테스트 프록시로 실제 키 흐름을 그대로 확인한다.
    func restore() {
        guard let key = activeKey, !key.isEmpty else {
            isSupporter = false
            return
        }
        // 우선 캐시(유예) 기준으로 잠정 결정한 뒤, 백그라운드 재검증.
        isSupporter = withinOfflineGrace()
        Task { await revalidate(key: key, silent: true) }
    }

    /// 유예 기간 안에 있는지(마지막 성공 검증 기준).
    private func withinOfflineGrace() -> Bool {
        guard let last = defaults.object(forKey: Key.lastValidated) as? Date else { return false }
        return Date().timeIntervalSince(last) < Self.offlineGrace
    }

    // MARK: - 키 활성화 / 해제

    /// 사용자가 입력한 키를 검증하고, 유효하면 저장·활성화한다.
    func activate(key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "키를 입력하세요."
            return
        }
        isValidating = true
        defer { isValidating = false }

        // 같은 기기에서 활성화를 반복하면 등록이 하나씩 새로 쌓여 5대 한도를 혼자 다 먹는다.
        // 이전 등록이 남아 있으면 먼저 반납하고 새로 등록한다.
        if let previousKey = activeKey, let previousInstance = instanceId {
            _ = await provider.deactivate(key: previousKey, instanceId: previousInstance)
            instanceId = nil
        }

        // 검증이 아니라 활성화다. 이 기기를 서버에 등록해야 활성화 한도가 의미를 갖고,
        // 나중에 이 기기만 골라 해제할 수 있다.
        switch await provider.activate(key: trimmed, instanceName: instanceName) {
        case .activated(let instance, let email, _):
            Self.saveKeyToKeychain(trimmed)
            activeKey = trimmed
            instanceId = instance
            defaults.set(Date(), forKey: Key.lastValidated)
            if let email { defaults.set(email, forKey: Key.cachedEmail) }
            isSupporter = true
            statusMessage = "후원자 키가 활성화되었습니다. 고맙습니다!" + (email.map { " (\($0))" } ?? "")
        case .limitReached:
            isSupporter = false
            statusMessage = "이 키는 이미 최대 기기 수만큼 사용 중입니다. 쓰지 않는 기기에서 해제한 뒤 다시 시도하세요."
        case .rejected(let reason):
            isSupporter = false
            statusMessage = "유효하지 않은 키: \(reason)"
        case .unreachable(let reason):
            // 서버에 못 닿은 것뿐이므로 키를 버리지 않는다. 사용자가 다시 시도하면 된다.
            statusMessage = "검증 실패(네트워크): \(reason)"
        }
    }

    /// 저장된 키로 재검증(시작 시 또는 수동 새로고침).
    /// silent=true면 성공 메시지를 조용히 처리(시작 시 방해 방지).
    func revalidate(key: String, silent: Bool) async {
        isValidating = true
        defer { isValidating = false }

        switch await provider.validate(key: key, instanceId: instanceId) {
        case .valid:
            defaults.set(Date(), forKey: Key.lastValidated)
            isSupporter = true
            if !silent { statusMessage = "후원자 키 확인됨" }
        case .invalid(let reason):
            // 서버가 명확히 무효라고 하면 후원자 상태 해제.
            isSupporter = false
            statusMessage = "후원자 키 무효: \(reason)"
        case .unreachable:
            // 검증 불가면 유예 기간 동안 기존 상태 유지.
            isSupporter = withinOfflineGrace()
            if !silent { statusMessage = "오프라인 — 유예 기간 동안 후원자 상태 유지" }
        }
    }

    /// 후원자 키 해제. 서버의 활성화 슬롯을 반납하고 이 기기에서 키를 지운다.
    ///
    /// 서버 반납이 실패해도 로컬 해제는 진행한다. 사용자를 붙잡아 둘 이유가 없기 때문이다.
    /// 대신 슬롯이 남아 있을 수 있다는 사실을 알려서, 다른 기기가 막히면 원인을 알 수 있게 한다.
    func deactivate() async {
        var slotReleased = true
        if let key = activeKey, let instance = instanceId {
            isValidating = true
            slotReleased = await provider.deactivate(key: key, instanceId: instance)
            isValidating = false
        }

        Self.deleteKeyFromKeychain()
        activeKey = nil
        instanceId = nil
        defaults.removeObject(forKey: Key.lastValidated)
        defaults.removeObject(forKey: Key.cachedEmail)
        isSupporter = false
        statusMessage = slotReleased
            ? "후원자 키가 해제되었습니다."
            : "이 기기에서는 해제했지만 서버에 반납하지 못했습니다. 활성화 한도가 그대로일 수 있습니다."
    }

    // MARK: - Keychain 저장소

    private static func saveKeyToKeychain(_ key: String) {
        deleteKeyFromKeychain()
        guard let data = key.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func readKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    private static func deleteKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
