import Foundation

/// Счётчик байт по MAC для прозрачного MITM-монитора. Держит отдельный /dev/bpf со снятым ARP-фильтром (ловит все
/// кадры, усечённые до заголовка — платим только за заголовок, длину берём из
/// bh_datalen). Считает трафик лишь для «интересных» MAC (найденные устройства);
/// служебный/широковещательный шум игнорируется.
///
/// Работает только когда мы — прозрачный MITM (forwarding ON): тогда пакеты
/// цели физически идут через нас. Никого не режет — только измеряет.
public final class TrafficMeter {
    private let bpf: BPFDevice
    private var interest: Set<MACAddress>
    private var bytes: [MACAddress: UInt64] = [:]
    private var windowStart = Date()

    /// fd капающего BPF — чтобы serve мог добавить его в свой poll().
    public var fd: Int32 { bpf.fd }

    public init(interface: String, interest: Set<MACAddress>) throws {
        self.bpf = try BPFDevice(interface: interface, countMode: true)
        self.interest = interest
    }

    public func setInterest(_ macs: Set<MACAddress>) { interest = macs }

    /// Слить доступные кадры без блокировки и прибавить байты к MAC на наших концах.
    /// В MITM каждый payload виден на плече «устройство↔мы» ровно один раз: на
    /// другом плече «мы↔шлюз» оба MAC не из interest, поэтому двойного учёта нет.
    public func drain() {
        for f in bpf.receiveSized(timeoutMS: 0) {
            if interest.contains(f.src) { bytes[f.src, default: 0] += UInt64(f.len) }
            if interest.contains(f.dst) { bytes[f.dst, default: 0] += UInt64(f.len) }
        }
    }

    /// KB/s по каждому interest-MAC за прошедшее окно; окно сбрасывается.
    /// Возвращает и простаивающие (0.0), чтобы GUI показал ноль, а не пропуск.
    public func rates() -> [MACAddress: Double] {
        let now = Date()
        let dt = max(0.001, now.timeIntervalSince(windowStart))
        var out: [MACAddress: Double] = [:]
        for m in interest { out[m] = Double(bytes[m] ?? 0) / 1024.0 / dt }
        bytes.removeAll()
        windowStart = now
        return out
    }
}
