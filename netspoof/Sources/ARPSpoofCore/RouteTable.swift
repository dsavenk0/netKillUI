import Foundation
import CBPF

/// IP шлюза по умолчанию через PF_ROUTE (sysctl), без внешних подпроцессов.
public func defaultGatewayIP() -> IPv4Address? {
    var out = [UInt8](repeating: 0, count: 4)
    guard cbpf_default_gateway(&out) == 0 else { return nil }
    return IPv4Address(bytes: out)
}

/// Шлюз для конкретного интерфейса. Если дефолтный маршрут идёт через нашу
/// подсеть — он и есть. Иначе (например, активен VPN и default через utun) —
/// типовой роутер подсети: network+1. Можно переопределить флагом -g.
public func gatewayGuess(for iface: InterfaceInfo) -> IPv4Address? {
    guard let mask = iface.netmask else { return defaultGatewayIP() }
    let net = iface.ip.hostOrder & mask.hostOrder
    if let gw = defaultGatewayIP(), (gw.hostOrder & mask.hostOrder) == net {
        return gw
    }
    return IPv4Address(hostOrder: net | 1)
}

/// Завершить все другие процессы netspoof (кроме себя) — единственный экземпляр
/// демона. Демон root, поэтому может убрать и прежние root-демоны-сироты.
public func killOtherNetspoofInstances() {
    cbpf_kill_other_netspoof()
}

/// Чтение/запись net.inet.ip.forwarding через sysctl.
public func getIPForwarding() -> Int32 {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    if sysctlbyname("net.inet.ip.forwarding", &value, &size, nil, 0) != 0 {
        return -1
    }
    return value
}

@discardableResult
public func setIPForwarding(_ on: Bool) -> Bool {
    var value: Int32 = on ? 1 : 0
    return sysctlbyname("net.inet.ip.forwarding", nil, nil, &value, MemoryLayout<Int32>.size) == 0
}
