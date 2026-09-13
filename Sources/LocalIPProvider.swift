import Foundation

/// 로컬(사설) IPv4 주소를 조회하는 유틸리티.
///
/// macOS의 `getifaddrs(3)`로 활성 네트워크 인터페이스를 훑어
/// 실제로 통신에 쓰이는 주 IPv4 주소를 골라낸다. 루프백(lo0)과
/// 링크로컬(169.254.x.x)은 제외하며, Wi-Fi(en0)를 이더넷보다
/// 우선하도록 인터페이스 이름 우선순위를 둔다.
enum LocalIPProvider {
    /// 인터페이스 이름 + 그 인터페이스에 바인딩된 IPv4 주소 한 줄.
    struct Interface: Identifiable {
        var id: String { name + address }
        let name: String        // 예: "en0"
        let address: String     // 예: "192.168.0.42"
    }

    /// 통신에 쓰일 가능성이 높은 주 IPv4 주소. 없으면 nil.
    /// Wi-Fi(en0) → 이더넷(en1…) → 기타 순으로 선호한다.
    static var primaryIPv4: String? {
        let candidates = ipv4Interfaces()
        // 인터페이스 이름 우선순위로 정렬해 가장 앞선 것을 고른다.
        return candidates.min(by: { rank($0.name) < rank($1.name) })?.address
    }

    /// 루프백/링크로컬을 제외한 모든 IPv4 인터페이스.
    static func ipv4Interfaces() -> [Interface] {
        var result: [Interface] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            // 인터페이스가 UP & RUNNING 상태여야 하고 루프백은 제외.
            guard (flags & IFF_UP) == IFF_UP,
                  (flags & IFF_RUNNING) == IFF_RUNNING,
                  (flags & IFF_LOOPBACK) == 0,
                  let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let salen = socklen_t(addr.pointee.sa_len)
            guard getnameinfo(addr, salen, &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(cString: host)
            // 링크로컬(169.254.x.x)은 실사용 주소가 아니므로 제외.
            if address.hasPrefix("169.254.") { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            result.append(Interface(name: name, address: address))
        }
        return result
    }

    /// 인터페이스 이름 정렬 우선순위(작을수록 우선).
    private static func rank(_ name: String) -> Int {
        switch name {
        case "en0": return 0   // 보통 Wi-Fi
        case let n where n.hasPrefix("en"): return 1   // 기타 이더넷/Wi-Fi
        default: return 2
        }
    }
}
