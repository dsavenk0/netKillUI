import Foundation

/// Скользящее среднее байт/сек по MAC за окно `window` секунд. Чистая логика без
/// BPF — поэтому тестируется напрямую (с инъекцией «текущего времени»). Учёт
/// взвешен по длительности сэмпла (dt), поэтому корректен и при неравномерных
/// интервалах вызова (например, когда цикл демона застрял на скане).
public struct RateWindow {
    public let window: TimeInterval
    private var samples: [MACAddress: [(t: Date, bytes: UInt64, dt: TimeInterval)]] = [:]
    private var lastSample: Date

    public init(window: TimeInterval = 5.0, now: Date = Date()) {
        self.window = window
        self.lastSample = now
    }

    /// Зафиксировать накопленные с прошлого раза байты как сэмпл и подрезать окно.
    public mutating func record(_ accumulated: [MACAddress: UInt64],
                                interest: Set<MACAddress>, now: Date) {
        let dt = max(0, now.timeIntervalSince(lastSample))
        lastSample = now
        for m in interest {
            samples[m, default: []].append((now, accumulated[m] ?? 0, dt))
        }
        let cutoff = now.addingTimeInterval(-window)
        for (m, arr) in samples {
            if interest.contains(m) {
                samples[m] = arr.filter { $0.t >= cutoff }
            } else {
                samples[m] = nil   // устройство вышло из интереса — забываем
            }
        }
    }

    /// KB/s по окну: суммарные байты за окно / суммарное время за окно.
    public func rates(interest: Set<MACAddress>) -> [MACAddress: Double] {
        var out: [MACAddress: Double] = [:]
        for m in interest {
            let arr = samples[m] ?? []
            let bytes = arr.reduce(0.0) { $0 + Double($1.bytes) }
            let secs = arr.reduce(0.0) { $0 + $1.dt }
            out[m] = secs > 0.1 ? bytes / 1024.0 / secs : 0
        }
        return out
    }
}

/// Счётчик байт по MAC для прозрачного MITM-монитора. Держит отдельный /dev/bpf
/// со снятым ARP-фильтром (ловит все кадры, усечённые до заголовка — платим лишь
/// за заголовок, длину берём из bh_datalen). Считает трафик только для «интересных»
/// MAC (найденные устройства); служебный/широковещательный шум игнорируется.
///
/// Работает только когда мы — прозрачный MITM (forwarding ON): тогда пакеты цели
/// физически идут через нас. Никого не режет — только измеряет. Отдаёт не
/// мгновенную скорость, а скользящее среднее KB/s (см. `RateWindow`).
public final class TrafficMeter {
    private let bpf: BPFDevice
    private var interest: Set<MACAddress>
    private var current: [MACAddress: UInt64] = [:]   // накопление с прошлого rates()
    private var win: RateWindow

    /// fd капающего BPF — чтобы serve мог добавить его в свой poll().
    public var fd: Int32 { bpf.fd }

    public init(interface: String, interest: Set<MACAddress>, window: TimeInterval = 5.0) throws {
        self.bpf = try BPFDevice(interface: interface, countMode: true)
        self.interest = interest
        self.win = RateWindow(window: window)
    }

    public func setInterest(_ macs: Set<MACAddress>) { interest = macs }

    /// Слить доступные кадры без блокировки и прибавить байты к MAC на наших концах.
    /// В MITM каждый payload виден на плече «устройство↔мы» ровно один раз: на
    /// другом плече «мы↔шлюз» оба MAC не из interest, поэтому двойного учёта нет.
    public func drain() {
        for f in bpf.receiveSized(timeoutMS: 0) {
            if interest.contains(f.src) { current[f.src, default: 0] += UInt64(f.len) }
            if interest.contains(f.dst) { current[f.dst, default: 0] += UInt64(f.len) }
        }
    }

    /// Скользящее среднее KB/s по окну. Вызывается периодически (≈раз в секунду).
    /// Возвращает и простаивающие (0.0), чтобы GUI показал ноль, а не пропуск.
    public func rates() -> [MACAddress: Double] {
        win.record(current, interest: interest, now: Date())
        current.removeAll()
        return win.rates(interest: interest)
    }
}
