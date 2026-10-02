import Foundation

/// Имена устройств через Bonjour/mDNS. Многие устройства (особенно iPhone/iPad/
/// Mac) не отвечают на обратный DNS, но анонсируют своё имя как инстанс
/// Bonjour-сервиса (_companion-link, _airplay и т.п.). Браузим пачку типов,
/// резолвим их в адреса и строим карту IP → имя.
final class BonjourResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private var browsers: [NetServiceBrowser] = []
    private var pending = Set<NetService>()
    private var ipToName: [String: String] = [:]
    private let lock = NSLock()

    private static let serviceTypes = [
        "_companion-link._tcp.",   // iPhone/iPad/Mac — имя = имя устройства
        "_airplay._tcp.", "_raop._tcp.",
        "_device-info._tcp.",
        "_rdlink._tcp.", "_apple-mobdev2._tcp.",
        "_ssh._tcp.", "_sftp-ssh._tcp.",
        "_smb._tcp.", "_afpovertcp._tcp.",
        "_http._tcp.", "_ipp._tcp.", "_printer._tcp.",
        "_googlecast._tcp.", "_spotify-connect._tcp.",
    ]

    /// Браузить заданное время (блокирует вызывающий поток, нужен его RunLoop).
    func browse(duration: TimeInterval) -> [String: String] {
        for type in Self.serviceTypes {
            let b = NetServiceBrowser()
            b.includesPeerToPeer = true
            b.delegate = self
            b.searchForServices(ofType: type, inDomain: "local.")
            browsers.append(b)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
        for b in browsers { b.stop() }
        lock.lock(); let result = ipToName; lock.unlock()
        return result
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        pending.insert(service) // удержать, пока резолвится
        service.resolve(withTimeout: 3.0)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let name = sender.name
        if !name.isEmpty, let addrs = sender.addresses {
            for data in addrs {
                if let ip = ipv4(from: data) {
                    lock.lock()
                    if ipToName[ip] == nil { ipToName[ip] = name }
                    lock.unlock()
                }
            }
        }
        pending.remove(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        pending.remove(sender)
    }

    private func ipv4(from data: Data) -> String? {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> String? in
            guard raw.count >= MemoryLayout<sockaddr_in>.size else { return nil }
            let fam = raw.loadUnaligned(fromByteOffset: 0, as: sockaddr.self).sa_family
            guard fam == UInt8(AF_INET) else { return nil }
            var sin = raw.loadUnaligned(fromByteOffset: 0, as: sockaddr_in.self)
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN))
            return String(cString: buf)
        }
    }
}

/// Запустить Bonjour-браузинг на выделенном потоке с RunLoop и вернуть карту IP→имя.
public func resolveDeviceNames(duration: TimeInterval = 2.5) -> [String: String] {
    let resolver = BonjourResolver()
    var result: [String: String] = [:]
    let sem = DispatchSemaphore(value: 0)
    let thread = Thread {
        result = resolver.browse(duration: duration)
        sem.signal()
    }
    thread.stackSize = 1 << 20
    thread.start()
    _ = sem.wait(timeout: .now() + duration + 1.0)
    return result
}
