import Foundation

/// Сетевое имя устройства по IP: reverse-DNS, на macOS заодно и mDNS (.local).
/// Блокирующий вызов (таймаут резолвера), поэтому в scan зовётся параллельно.
public func hostname(for ip: IPv4Address) -> String? {
    var sin = sockaddr_in()
    sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    sin.sin_family = sa_family_t(AF_INET)
    sin.sin_addr.s_addr = ip.networkOrder

    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    let rc = withUnsafePointer(to: &sin) { p in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            getnameinfo(sa, socklen_t(MemoryLayout<sockaddr_in>.size),
                        &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
        }
    }
    guard rc == 0 else { return nil }

    var name = String(cString: host)
    if name.hasSuffix(".") { name = String(name.dropLast()) }
    if name.isEmpty || name == ip.description { return nil }
    return name
}
