import Foundation
import CBPF

/// Статическая маскировка собственного MAC: один раз при старте движка подменяем
/// аппаратный адрес интерфейса на правдоподобный (префикс реального вендора +
/// случайный хвост), чтобы скрыть личность нашего устройства в сети. НЕ ротация —
/// адрес держится всю сессию, при выходе восстанавливается оригинал.
///
/// Честно: на Wi-Fi смена MAC требует down/up (краткий обрыв связи) и может не
/// закрепиться (ОС откатывает). Поэтому apply() перечитывает MAC и возвращает
/// правду — применилось или нет; вызывающий не должен давать ложную анонимность.
public enum MACMasker {
    /// Текущий аппаратный MAC интерфейса.
    public static func current(_ iface: String) -> MACAddress? {
        var b = [UInt8](repeating: 0, count: 6)
        return cbpf_get_mac(iface, &b) == 0 ? MACAddress(bytes: b) : nil
    }

    /// Интерфейс — Wi-Fi? На встроенном Wi-Fi Apple Silicon смена MAC не держится,
    /// поэтому там маскировку не пытаемся делать (не дёргаем связь впустую).
    public static func isWiFi(_ iface: String) -> Bool {
        cbpf_is_wifi(iface) != 0
    }

    /// Применить MAC (down→lladdr→up) и проверить, что он реально закрепился.
    @discardableResult
    public static func apply(_ iface: String, _ mac: MACAddress) -> Bool {
        var m = mac.bytes
        _ = cbpf_set_mac(iface, &m)
        usleep(500_000)                 // дать интерфейсу переварить смену
        return current(iface) == mac
    }

    /// Правдоподобный случайный MAC: префикс реального вендора (OUI) + случайные
    /// 3 байта. Юникаст, бит locally-administered НЕ ставим — чтобы выглядел как
    /// настоящее устройство вендора, а не как явно рандомизированный адрес.
    public static func plausible() -> MACAddress {
        let ouis: [[UInt8]] = [
            [0x3c, 0x22, 0xfb], // Apple
            [0xf0, 0x18, 0x98], // Apple
            [0xa4, 0x83, 0xe7], // Apple
            [0x5c, 0x96, 0x9d], // Apple
            [0x50, 0x32, 0x37], // Samsung
            [0x00, 0x1a, 0x11], // Google
            [0xb8, 0x27, 0xeb], // Raspberry Pi
            [0xdc, 0xa6, 0x32], // Raspberry Pi
        ]
        let oui = ouis.randomElement()!
        let tail = (0..<3).map { _ in UInt8.random(in: 0...255) }
        return MACAddress(bytes: oui + tail)
    }
}
