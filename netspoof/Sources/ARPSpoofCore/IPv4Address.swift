import Foundation

public struct IPv4Address: Equatable, Hashable, CustomStringConvertible {
    public let bytes: [UInt8] // 4 октета, bytes[0] — старший (как в "a.b.c.d")

    public init(bytes: [UInt8]) {
        precondition(bytes.count == 4)
        self.bytes = bytes
    }

    public init?(_ string: String) {
        var addr = in_addr()
        guard inet_pton(AF_INET, string, &addr) == 1 else { return nil }
        self.init(networkOrder: addr.s_addr)
    }

    /// Из in_addr.s_addr (network byte order).
    public init(networkOrder raw: UInt32) {
        self.bytes = [
            UInt8(raw & 0xff),
            UInt8((raw >> 8) & 0xff),
            UInt8((raw >> 16) & 0xff),
            UInt8((raw >> 24) & 0xff),
        ]
    }

    /// Из host-order UInt32 (для арифметики по подсети).
    public init(hostOrder v: UInt32) {
        self.bytes = [
            UInt8((v >> 24) & 0xff),
            UInt8((v >> 16) & 0xff),
            UInt8((v >> 8) & 0xff),
            UInt8(v & 0xff),
        ]
    }

    public var hostOrder: UInt32 {
        (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) |
            (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }

    /// Значение для in_addr.s_addr (network byte order).
    public var networkOrder: UInt32 {
        UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) |
            (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
    }

    public var description: String {
        bytes.map(String.init).joined(separator: ".")
    }
}

/// Перечислить хосты внутри подсети (без network/broadcast адресов).
public func hostsInSubnet(ip: IPv4Address, mask: IPv4Address, cap: Int = 1024) -> [IPv4Address] {
    let ipv = ip.hostOrder
    let maskv = mask.hostOrder
    let network = ipv & maskv
    let broadcast = network | ~maskv
    guard broadcast > network + 1 else { return [] }

    var result = [IPv4Address]()
    var h = network &+ 1
    while h < broadcast && result.count < cap {
        result.append(IPv4Address(hostOrder: h))
        h &+= 1
    }
    return result
}
