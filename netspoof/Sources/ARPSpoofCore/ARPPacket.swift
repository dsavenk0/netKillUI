import Foundation

public enum ARPOp: UInt16 {
    case request = 1
    case reply = 2
}

/// Собрать Ethernet-кадр (14 байт) + ARP-пакет (28 байт) для IPv4/Ethernet.
public func buildARPFrame(op: ARPOp,
                          senderMAC: MACAddress, senderIP: IPv4Address,
                          targetMAC: MACAddress, targetIP: IPv4Address,
                          ethDst: MACAddress, ethSrc: MACAddress) -> [UInt8] {
    var f = [UInt8]()
    f.reserveCapacity(42)

    // --- Ethernet header ---
    f += ethDst.bytes
    f += ethSrc.bytes
    f += [0x08, 0x06] // ethertype = ARP

    // --- ARP payload ---
    f += [0x00, 0x01]       // HTYPE = Ethernet
    f += [0x08, 0x00]       // PTYPE = IPv4
    f += [0x06]             // HLEN
    f += [0x04]             // PLEN
    let opv = op.rawValue
    f += [UInt8(opv >> 8), UInt8(opv & 0xff)]
    f += senderMAC.bytes
    f += senderIP.bytes
    f += targetMAC.bytes
    f += targetIP.bytes

    // Минимальный Ethernet-кадр — 60 байт (без FCS). Драйвер обычно паддит сам,
    // но добьём нулями для совместимости.
    if f.count < 60 {
        f += [UInt8](repeating: 0, count: 60 - f.count)
    }
    return f
}

/// Если кадр — это ARP reply, вернуть (sender MAC, sender IP).
public func parseARPReply(_ frame: [UInt8]) -> (MACAddress, IPv4Address)? {
    guard frame.count >= 42 else { return nil }
    guard frame[12] == 0x08, frame[13] == 0x06 else { return nil }   // ethertype ARP
    guard frame[20] == 0x00, frame[21] == 0x02 else { return nil }   // op = reply

    let senderMAC = MACAddress(bytes: Array(frame[22..<28]))
    let senderIP = IPv4Address(bytes: Array(frame[28..<32]))
    return (senderMAC, senderIP)
}

/// Из любого ARP-кадра (request или reply) вытащить (sender MAC, sender IP).
/// Нужно для живого отслеживания связки MAC → текущий IP. ARP-пробы (0.0.0.0) пропускаются.
public func parseARPSender(_ frame: [UInt8]) -> (MACAddress, IPv4Address)? {
    guard frame.count >= 42 else { return nil }
    guard frame[12] == 0x08, frame[13] == 0x06 else { return nil }     // ethertype ARP
    guard frame[20] == 0x00, frame[21] == 0x01 || frame[21] == 0x02 else { return nil } // op 1/2

    let senderMAC = MACAddress(bytes: Array(frame[22..<28]))
    let senderIP = IPv4Address(bytes: Array(frame[28..<32]))
    if senderIP.bytes == [0, 0, 0, 0] { return nil }
    return (senderMAC, senderIP)
}
