import Foundation

/// Абстракция «того, кто рассылает/слушает ARP», от которой зависит `SpoofEngine`.
/// Реальная реализация — `ARPSpoofer` (поверх BPF, требует root). Благодаря этому
/// шву логику движка (кого травить, детект, блок-на-появление) можно юнит-тестить
/// с подставным спаем, без открытия /dev/bpf.
public protocol ARPSpoofing: AnyObject {
    var iface: InterfaceInfo { get }

    func discoverHosts(duration: TimeInterval) -> [Host]
    func discoverHostsPassive(duration: TimeInterval) -> [Host]
    func resolveNames(for hosts: [Host], duration: TimeInterval) -> [MACAddress: String]

    func probeSubnet()
    func poisonOnce(victimIP: IPv4Address, victimMAC: MACAddress,
                    gatewayIP: IPv4Address, gatewayMAC: MACAddress,
                    oneway: Bool, route: MACAddress?)
    func restore(victimIP: IPv4Address, victimMAC: MACAddress,
                 gatewayIP: IPv4Address, gatewayMAC: MACAddress, times: Int)
}

// Удобные no-arg варианты с теми же умолчаниями, что у ARPSpoofer — чтобы вызовы
// через `any ARPSpoofing` (например, в serve) оставались прежними.
public extension ARPSpoofing {
    func discoverHosts() -> [Host] { discoverHosts(duration: 2.5) }
    func discoverHostsPassive() -> [Host] { discoverHostsPassive(duration: 6.0) }
    func resolveNames(for hosts: [Host]) -> [MACAddress: String] {
        resolveNames(for: hosts, duration: 2.5)
    }
}
