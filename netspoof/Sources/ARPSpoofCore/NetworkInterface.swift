import Foundation
import CBPF

public struct InterfaceInfo {
    public let name: String
    public let mac: MACAddress
    public let ip: IPv4Address
    public let netmask: IPv4Address?

    public init(name: String, mac: MACAddress, ip: IPv4Address, netmask: IPv4Address?) {
        self.name = name
        self.mac = mac
        self.ip = ip
        self.netmask = netmask
    }
}

public enum NetworkError: Error, CustomStringConvertible {
    case interfaceNotFound(String)
    case noMAC(String)
    case noIPv4(String)

    public var description: String {
        switch self {
        case .interfaceNotFound(let n): return "Интерфейс \(n) не найден"
        case .noMAC(let n): return "Не удалось получить MAC для \(n)"
        case .noIPv4(let n): return "У \(n) нет IPv4-адреса"
        }
    }
}

private func sockaddrToIPv4(_ sa: UnsafePointer<sockaddr>) -> IPv4Address? {
    guard sa.pointee.sa_family == UInt8(AF_INET) else { return nil }
    return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
        IPv4Address(networkOrder: sin.pointee.sin_addr.s_addr)
    }
}

public func queryInterface(_ name: String) throws -> InterfaceInfo {
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0 else {
        throw NetworkError.interfaceNotFound(name)
    }
    defer { freeifaddrs(ifap) }

    var mac: MACAddress?
    var ip: IPv4Address?
    var mask: IPv4Address?
    var seen = false

    var ptr = ifap
    while let cur = ptr {
        let ifa = cur.pointee
        defer { ptr = ifa.ifa_next }

        let ifname = String(cString: ifa.ifa_name)
        guard ifname == name, let sa = ifa.ifa_addr else { continue }
        seen = true

        let family = sa.pointee.sa_family
        if family == UInt8(AF_LINK) {
            var out = [UInt8](repeating: 0, count: 6)
            if cbpf_sdl_mac(sa, &out) == 0 {
                mac = MACAddress(bytes: out)
            }
        } else if family == UInt8(AF_INET) {
            ip = sockaddrToIPv4(sa)
            if let nm = ifa.ifa_netmask {
                mask = sockaddrToIPv4(nm)
            }
        }
    }

    guard seen else { throw NetworkError.interfaceNotFound(name) }
    guard let m = mac else { throw NetworkError.noMAC(name) }
    guard let i = ip else { throw NetworkError.noIPv4(name) }
    return InterfaceInfo(name: name, mac: m, ip: i, netmask: mask)
}

/// Активные IPv4-интерфейсы (UP, не loopback) — для выпадающего списка.
public func listIPv4Interfaces() -> [String] {
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0 else { return [] }
    defer { freeifaddrs(ifap) }

    var names: [String] = []
    var ptr = ifap
    while let cur = ptr {
        let ifa = cur.pointee
        defer { ptr = ifa.ifa_next }
        guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
        let flags = ifa.ifa_flags
        guard flags & UInt32(IFF_UP) != 0,
              flags & UInt32(IFF_LOOPBACK) == 0,
              flags & UInt32(IFF_POINTOPOINT) == 0,   // исключить VPN/туннели (utun, ppp)
              flags & UInt32(IFF_BROADCAST) != 0 else { continue } // ARP нужен broadcast
        let name = String(cString: ifa.ifa_name)
        if !names.contains(name) { names.append(name) }
    }
    return names
}

/// Интерфейс, через который идёт трафик по умолчанию: тот, в чьей подсети
/// лежит шлюз по умолчанию. Фолбэк — первый активный IPv4-интерфейс.
public func activeInterface() -> String? {
    let gw = defaultGatewayIP()
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0 else { return nil }
    defer { freeifaddrs(ifap) }

    var firstUp: String?
    var ptr = ifap
    while let cur = ptr {
        let ifa = cur.pointee
        defer { ptr = ifa.ifa_next }
        guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
        let flags = ifa.ifa_flags
        guard flags & UInt32(IFF_UP) != 0,
              flags & UInt32(IFF_LOOPBACK) == 0,
              flags & UInt32(IFF_POINTOPOINT) == 0,   // исключить VPN/туннели
              flags & UInt32(IFF_BROADCAST) != 0 else { continue }
        let name = String(cString: ifa.ifa_name)
        guard let ip = sockaddrToIPv4(sa) else { continue }
        if firstUp == nil { firstUp = name }

        if let gw, let nm = ifa.ifa_netmask, let mask = sockaddrToIPv4(nm),
           (ip.hostOrder & mask.hostOrder) == (gw.hostOrder & mask.hostOrder) {
            return name
        }
    }
    return firstUp
}
