import Foundation
import CBPF

public enum BPFError: Error, CustomStringConvertible {
    case noDevice
    case bindFailed(String, Int32)
    case writeFailed(Int32)

    public var description: String {
        switch self {
        case .noDevice:
            return "Не удалось открыть ни одно /dev/bpfN (нужен root?)"
        case .bindFailed(let ifn, let e):
            return "BIOCSETIF для \(ifn) не удался (errno=\(e))"
        case .writeFailed(let e):
            return "Запись в BPF не удалась (errno=\(e))"
        }
    }
}

/// Обёртка над /dev/bpfN: inject + capture Ethernet-кадров на интерфейсе.
public final class BPFDevice {
    public let fd: Int32
    public let bufferLength: Int

    public init(interface: String, arpOnly: Bool = true) throws {
        var opened: Int32 = -1
        for i in 0..<256 {
            let f = open("/dev/bpf\(i)", O_RDWR)
            if f >= 0 { opened = f; break }
            if errno == EBUSY { continue } // устройство занято — пробуем следующее
        }
        guard opened >= 0 else { throw BPFError.noDevice }
        self.fd = opened

        // Размер буфера задаётся ДО привязки к интерфейсу.
        _ = cbpf_set_blen(fd, 32768)

        if cbpf_set_interface(fd, interface) != 0 {
            let e = errno
            close(fd)
            throw BPFError.bindFailed(interface, e)
        }

        _ = cbpf_set_immediate(fd, 1)
        _ = cbpf_set_header_complete(fd, 1)
        if arpOnly {
            _ = cbpf_set_arp_filter(fd)
        }

        var got: UInt32 = 0
        _ = cbpf_get_blen(fd, &got)
        self.bufferLength = got > 0 ? Int(got) : 32768
    }

    deinit {
        close(fd)
    }

    public func send(_ frame: [UInt8]) throws {
        let n = frame.withUnsafeBytes { raw in
            write(fd, raw.baseAddress, raw.count)
        }
        if n < 0 { throw BPFError.writeFailed(errno) }
    }

    /// Прочитать доступные кадры, ожидая не дольше timeoutMS.
    public func receive(timeoutMS: Int32) -> [[UInt8]] {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let r = poll(&pfd, 1, timeoutMS)
        if r <= 0 { return [] }

        var buf = [UInt8](repeating: 0, count: bufferLength)
        let n = buf.withUnsafeMutableBytes { raw in
            read(fd, raw.baseAddress, raw.count)
        }
        if n <= 0 { return [] }

        var frames = [[UInt8]]()
        buf.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < n {
                let p = base.advanced(by: offset)
                let hdrlen = Int(cbpf_hdr_len(p))
                let caplen = Int(cbpf_caplen(p))
                let start = offset + hdrlen
                if caplen > 0, start + caplen <= n {
                    frames.append(Array(raw[start..<start + caplen]))
                }
                let advance = Int(cbpf_wordalign(UInt32(hdrlen + caplen)))
                if advance <= 0 { break }
                offset += advance
            }
        }
        return frames
    }
}
