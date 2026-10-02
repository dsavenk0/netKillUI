import Foundation

/// Клиент unix-сокета к `netspoof serve`. Читает JSON построчно в фоне,
/// события отдаёт на главный поток.
final class SocketClient {
    private var fd: Int32 = -1
    // ВАЖНО: раздельные очереди. Цикл чтения блокирует свою очередь навсегда
    // (while true { read }), поэтому запись должна идти по отдельной очереди —
    // иначе send() встанет за чтением и никогда не выполнится.
    private let readQueue = DispatchQueue(label: "netkillui.socket.read")
    private let writeQueue = DispatchQueue(label: "netkillui.socket.write")

    var onEvent: (([String: Any]) -> Void)?
    var onClose: (() -> Void)?

    func connect(path: String) -> Bool {
        let f = socket(AF_UNIX, SOCK_STREAM, 0)
        guard f >= 0 else { return false }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let cap = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: cap) { dst in
                _ = strncpy(dst, path, cap - 1)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let r = withUnsafePointer(to: &addr) { ap in
            ap.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(f, $0, len) }
        }
        guard r == 0 else { Darwin.close(f); return false }
        fd = f
        startReading()
        return true
    }

    private func startReading() {
        let f = fd
        readQueue.async { [weak self] in
            var buf = [UInt8]()
            var tmp = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(f, &tmp, tmp.count)
                if n <= 0 { break }
                buf.append(contentsOf: tmp[0..<n])
                while let nl = buf.firstIndex(of: 0x0A) {
                    let line = Array(buf[0..<nl])
                    buf.removeSubrange(0...nl)
                    if let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                        DispatchQueue.main.async { self?.onEvent?(obj) }
                    }
                }
            }
            DispatchQueue.main.async { self?.onClose?() }
        }
    }

    func send(_ obj: [String: Any]) {
        guard fd >= 0, var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        data.append(0x0A)
        let f = fd
        writeQueue.async {
            data.withUnsafeBytes { _ = write(f, $0.baseAddress, $0.count) }
        }
    }

    func close() {
        if fd >= 0 { Darwin.close(fd); fd = -1 }
    }
}
